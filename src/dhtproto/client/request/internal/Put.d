/*******************************************************************************

    Client DHT Put v0 request handler.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.internal.Put;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.meta.types.Qualifiers;
import ocean.core.VersionCheck;
import ocean.util.log.Logger;

/*******************************************************************************

    Module logger

*******************************************************************************/

static private Logger log;
static this ( )
{
    log = Log.lookup("dhtproto.client.request.internal.Put");
}

/*******************************************************************************

    Put request implementation.

    Note that request structs act simply as namespaces for the collection of
    symbols required to implement a request. They are never instantiated and
    have no fields or non-static functions.

    The client expects several things to be present in a request struct:
        1. The static constants request_type and request_code
        2. The UserSpecifiedParams struct, containing all user-specified request
            setup (including a notifier)
        3. The Notifier delegate type
        4. Optionally, the Controller type (if the request can be controlled,
           after it has begun)
        5. The handler() function
        6. The all_finished_notifier() function

    The RequestCore mixin provides items 1 and 2.

*******************************************************************************/

public struct Put
{
    import dhtproto.common.Put;
    import dhtproto.client.request.Put;
    import dhtproto.common.RequestCodes;
    import swarm.neo.client.mixins.RequestCore;
    import swarm.neo.client.RequestHandlers;
    import swarm.neo.client.RequestOnConn;
    import swarm.neo.request.Command;
    import dhtproto.client.internal.SharedResources;

    import ocean.io.select.protocol.generic.ErrnoIOException: IOError;

    /***************************************************************************

        Data which the request needs while it is progress. An instance of this
        struct is stored per connection on which the request runs and is passed
        to the request handler.

    ***************************************************************************/

    private static struct SharedWorking
    {
        public enum Result
        {
            Failure,
            ValueTooBig,
            NoNode,
            Error,
            Success
        }

        Result result;
    }

    /***************************************************************************

        Request core. Mixes in the types `NotificationInfo`, `Notifier`,
        `Params`, `Context` plus the static constants `request_type` and
        `request_code`.

    ***************************************************************************/

    mixin RequestCore!(RequestType.SingleNode, RequestCode.Put, 0, Args,
        SharedWorking, Notification);

    /***************************************************************************

        Request handler. Called from RequestOnConn.runHandler().

        Params:
            use_node = delegate to get an EventDispatcher for the node with the
                specified address
            context_blob = untyped chunk of data containing the serialized
                context of the request which is to be handled

    ***************************************************************************/

    public static void handler ( UseNodeDg use_node, void[] context_blob )
    {
        auto context = Put.getContext(context_blob);
        context.shared_working.result = SharedWorking.Result.Failure;

        auto shared_resources = SharedResources.fromObject(
            context.shared_resources);
        scope acquired_resources = shared_resources.new RequestResources;

        if ( context.user_params.args.value.length > MaxRecordSize )
        {
            context.shared_working.result = SharedWorking.Result.ValueTooBig;
            return;
        }

        // Try putting the record to the newest node responsible for the hash.
        bool put_called;
        shared_resources.node_hash_ranges.putToNode(
            context.user_params.args.key,
            acquired_resources.getNodeHashRangeBuffer(), use_node,
            ( RequestOnConn.EventDispatcher conn )
            {
                put_called = true;
                putToNode(conn, context);
            }
        );

        if ( !put_called )
            context.shared_working.result = SharedWorking.Result.NoNode;
    }

    /***************************************************************************

        Puts the record passed by the user to the specified node.

        Params:
            conn = event dispatcher for the connection to send the record to
            context = deserialized request context, including record/value

    ***************************************************************************/

    private static void putToNode ( RequestOnConn.EventDispatcher conn,
        Put.Context* context )
    {
        try
        {
            // Send request info to node
            conn.send(
                ( conn.Payload payload )
                {
                    payload.add(Put.cmd.code);
                    payload.add(Put.cmd.ver);
                    payload.addArray(context.user_params.args.channel);
                    payload.add(context.user_params.args.key);
                    payload.addArray(context.user_params.args.value);
                }
            );

            // Receive supported code from node
            auto supported = conn.receiveValue!(SupportedStatus)();
            if ( !Put.handleSupportedCodes(supported, context,
                conn.remote_address) )
            {
                // Request not supported; abort further handling.
                context.shared_working.result = SharedWorking.Result.Error;
            }
            else
            {
                // Request supported; read result code from node.
                auto result = conn.receiveValue!(MessageType)();
                switch ( result )
                {
                    case MessageType.Put:
                        context.shared_working.result =
                            SharedWorking.Result.Success;
                        break;

                    case MessageType.WrongNode:
                        context.shared_working.result =
                            SharedWorking.Result.Error;

                        // The node is not reponsible for the key. Notify the user.
                        Notification n;
                        n.wrong_node = RequestNodeInfo(context.request_id,
                            conn.remote_address);
                        Put.notify(context.user_params, n);
                        break;

                    case MessageType.Error:
                        context.shared_working.result =
                            SharedWorking.Result.Error;

                        // The node returned an error code. Notify the user.
                        Notification n;
                        n.node_error = RequestNodeInfo(context.request_id,
                            conn.remote_address);
                        Put.notify(context.user_params, n);
                        break;

                    default:
                        log.warn("Received unknown message code {} from node "
                            ~ "in response to Put request. Treating as "
                            ~ "Error.", result);
                        goto case MessageType.Error;
                }
            }
        }
        catch ( IOError e )
        {
            context.shared_working.result =
                SharedWorking.Result.Error;

            // A connection error occurred. Notify the user.
            auto info = RequestNodeExceptionInfo(context.request_id,
                conn.remote_address, e);

            Notification n;
            n.node_disconnected = info;
            Put.notify(context.user_params, n);
        }
    }

    /***************************************************************************

        Request finished notifier. Called from Request.handlerFinished().

        Params:
            context_blob = untyped chunk of data containing the serialized
                context of the request which is finishing

    ***************************************************************************/

    public static void all_finished_notifier ( void[] context_blob )
    {
        auto context = Put.getContext(context_blob);

        Notification n;

        with ( SharedWorking.Result ) switch ( context.shared_working.result )
        {
            case Success:
                n.success = RequestInfo(context.request_id);
                break;
            case ValueTooBig:
                n.value_too_big = RequestInfo(context.request_id);
                break;
            case NoNode:
                n.no_node = RequestInfo(context.request_id);
                break;
            case Failure:
                n.failure = RequestInfo(context.request_id);
                break;
            case Error:
                // Error notification was already handled in putToNode(),
                // where we have access to the node's address &/ exception.
                return;
            default:
                assert(false);
        }

        Put.notify(context.user_params, n);
    }
}
