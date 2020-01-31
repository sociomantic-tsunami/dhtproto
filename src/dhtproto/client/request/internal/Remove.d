/*******************************************************************************

    Client DHT Remove v0 request handler.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.internal.Remove;

import ocean.meta.types.Qualifiers;
import ocean.core.VersionCheck;
import ocean.util.log.Logger;

/*******************************************************************************

    Module logger

*******************************************************************************/

static private Logger log;
static this ( )
{
    log = Log.lookup("dhtproto.client.request.internal.Remove");
}

/*******************************************************************************

    Remove request implementation.

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

public struct Remove
{
    import dhtproto.common.Remove;
    public import dhtproto.client.request.Remove;
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
        /// Enum indicating the ways in which the request may end.
        public enum Result
        {
            Failure,    // Default value; unknown error (presumably in client)
            NoNode,     // No node responsible for key
            Error,      // Node or I/O error
            NoRecord,   // Record not present
            Removed     // Removed record
        }

        /// The way in which the request ended. Used by the finished notifier to
        /// decide what kind of notification (if any) to send to the user.
        Result result;
    }

    /***************************************************************************

        Request core. Mixes in the types `NotificationInfo`, `Notifier`,
        `Params`, `Context` plus the static constants `request_type` and
        `request_code`.

    ***************************************************************************/

    mixin RequestCore!(RequestType.SingleNode, RequestCode.Remove, 0, Args,
        SharedWorking, Notification);

    /***************************************************************************

        Request handler. Called from RequestOnConn.runHandler().

        FIXME: Note that the logic for retrying the request on other nodes which
        previously covered the hash has not been properly tested. This will
        require a full neo implementation of the Redistribute request. See
        https://github.com/sociomantic-tsunami/dhtnode/issues/21

        Params:
            use_node = delegate to get an EventDispatcher for the node with the
                specified address
            context_blob = untyped chunk of data containing the serialized
                context of the request which is to be handled

    ***************************************************************************/

    public static void handler ( UseNodeDg use_node, void[] context_blob )
    {
        auto context = Remove.getContext(context_blob);
        context.shared_working.result = SharedWorking.Result.Failure;

        auto shared_resources = SharedResources.fromObject(
            context.shared_resources);
        scope acquired_resources = shared_resources.new RequestResources;

        // Remove the record from all nodes responsible for the hash, querying
        // them in oldest -> newest order
        bool dg_called;
        shared_resources.node_hash_ranges.removeFromNodes(
            context.user_params.args.key,
            acquired_resources.getNodeHashRangeBuffer(), use_node,
            ( RequestOnConn.EventDispatcher conn )
            {
                dg_called = true;
                return removeFromNode(conn, context);
            }
        );

        if ( !dg_called )
            // No node covers the record's hash
            context.shared_working.result = SharedWorking.Result.NoNode;
    }

    /***************************************************************************

        Tries to remove the record from the specified node.

        Params:
            conn = event dispatcher for the connection to send to
            context = deserialized request context

        Returns:
            true to continue to the next node, if removal succeeded (either the
            record was removed or it didn't exist in the node); false to abort
            the request, if an error occurred. Error cases abort the request
            (return false), because it is not possible to know if the node where
            the error occurred now has the record or not.

    ***************************************************************************/

    private static bool removeFromNode ( RequestOnConn.EventDispatcher conn,
        Remove.Context* context )
    {
        try
        {
            // Send request info to node
            conn.send(
                ( conn.Payload payload )
                {
                    payload.add(Remove.cmd.code);
                    payload.add(Remove.cmd.ver);
                    payload.addArray(context.user_params.args.channel);
                    payload.add(context.user_params.args.key);
                }
            );

            static if (!hasFeaturesFrom!("swarm", 4, 7))
                conn.flush();

            // Receive supported code from node
            auto supported = conn.receiveValue!(SupportedStatus)();
            if ( !Remove.handleSupportedCodes(supported, context,
                conn.remote_address) )
            {
                // Request not supported; abort further handling.
                context.shared_working.result = SharedWorking.Result.Error;
                return false;
            }
            else
            {
                // Request supported; read result code from node.
                auto result = conn.receiveValue!(MessageType)();
                with ( MessageType ) switch ( result )
                {
                    case Removed:
                        context.shared_working.result =
                            SharedWorking.Result.Removed;
                        return true;

                    case NoRecord:
                        context.shared_working.result =
                            SharedWorking.Result.NoRecord;
                        return true;

                    case WrongNode:
                        context.shared_working.result =
                            SharedWorking.Result.Error;

                        // The node is not reponsible for the key. Notify the user.
                        Notification n;
                        n.wrong_node = RequestNodeInfo(
                            context.request_id,conn.remote_address);
                        Remove.notify(context.user_params, n);
                        return false;

                    case Error:
                        context.shared_working.result =
                            SharedWorking.Result.Error;

                        // The node returned an error code. Notify the user.
                        Notification n;
                        n.node_error = RequestNodeInfo(context.request_id,
                            conn.remote_address);
                        Remove.notify(context.user_params, n);
                        return false;

                    default:
                        log.warn("Received unknown message code {} from node "
                            ~ "in response to Remove request. Treating as "
                            ~ "Error.", result);
                        goto case Error;
                }
            }

            assert(false);
        }
        catch ( IOError e )
        {
            context.shared_working.result = SharedWorking.Result.Error;

            // A connection error occurred. Notify the user.
            auto info = RequestNodeExceptionInfo(context.request_id,
                conn.remote_address, e);

            Notification n;
            n.node_disconnected = info;
            Remove.notify(context.user_params, n);

            return false;
        }

        assert(false);
    }

    /***************************************************************************

        Request finished notifier. Called from Request.handlerFinished().

        Params:
            context_blob = untyped chunk of data containing the serialized
                context of the request which is finishing

    ***************************************************************************/

    public static void all_finished_notifier ( void[] context_blob )
    {
        auto context = Remove.getContext(context_blob);

        Notification n;

        with ( SharedWorking.Result ) switch ( context.shared_working.result )
        {
            case Failure:
                n.failure = RequestInfo(context.request_id);
                break;
            case NoRecord:
                n.no_record = RequestInfo(context.request_id);
                break;
            case NoNode:
                n.no_node = RequestInfo(context.request_id);
                break;
            case Removed:
                n.removed = RequestInfo(context.request_id);
                break;
            case Error:
                // Error notification was already handled in getFromNode(),
                // where we have access to the node's address &/ exception.
                return;
            default:
                assert(false);
        }

        Remove.notify(context.user_params, n);
    }
}
