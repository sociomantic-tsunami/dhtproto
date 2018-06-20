/*******************************************************************************

    Client DHT Get v0 request handler.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.internal.Get;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;
import ocean.util.log.Logger;

/*******************************************************************************

    Module logger

*******************************************************************************/

static private Logger log;
static this ( )
{
    log = Log.lookup("dhtproto.client.request.internal.Get");
}

/*******************************************************************************

    Get request implementation.

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

public struct Get
{
    import dhtproto.common.Get;
    import dhtproto.client.request.Get;
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
            Timeout,    // Request timed out in client before completion
            NoNode,     // No node responsible for key
            Error,      // Node or I/O error
            NoRecord,   // Record not found
            Got         // Got record
        }

        /// The way in which the request ended. Used by the finished notifier to
        /// decide what kind of notification (if any) to send to the user.
        Result result;
    }

    /***************************************************************************

        Data which each request-on-conn needs while it is progress. An instance
        of this struct is stored per connection on which the request runs and is
        passed to the request handler.

    ***************************************************************************/

    private static struct Working
    {
        // Dummy (not required by this request)
    }

    /***************************************************************************

        Request core. Mixes in the types `NotificationInfo`, `Notifier`,
        `Params`, `Context` plus the static constants `request_type` and
        `request_code`.

    ***************************************************************************/

    mixin RequestCore!(RequestType.SingleNode, RequestCode.Get, 0, Args,
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
        auto context = Get.getContext(context_blob);
        context.shared_working.result = SharedWorking.Result.Failure;

        auto shared_resources = SharedResources.fromObject(
            context.shared_resources);
        scope acquired_resources = shared_resources.new RequestResources;

        // Try getting the record from the nodes responsible for the hash,
        // querying them in newest -> oldest order
        bool get_called;
        shared_resources.node_hash_ranges.getFromNode(
            context.user_params.args.key,
            acquired_resources.getNodeHashRangeBuffer(), use_node,
            ( RequestOnConn.EventDispatcher conn )
            {
                get_called = true;
                return getFromNode(conn, context);
            }
        );

        if ( !get_called )
        {
            // Bail out if no nodes cover the record's hash
            context.shared_working.result = SharedWorking.Result.NoNode;
            return;
        }
    }

    /***************************************************************************

        Tries to gets the record from the specified node.

        Params:
            conn = event dispatcher for the connection to send the record to
            context = deserialized request context, including record/value

        Returns:
            true to try another node, false if finished (the record was fetched
            or an error occurred). All error cases abort the request (return
            false), as it is not possible to know if the node where the error
            occurred has the record or not.

    ***************************************************************************/

    private static bool getFromNode ( RequestOnConn.EventDispatcher conn,
        Get.Context* context )
    {
        try
        {
            // Send request info to node
            conn.send(
                ( conn.Payload payload )
                {
                    payload.add(Get.cmd.code);
                    payload.add(Get.cmd.ver);
                    payload.addArray(context.user_params.args.channel);
                    payload.add(context.user_params.args.key);
                }
            );
            conn.flush();

            // Receive supported code from node
            auto supported = conn.receiveValue!(SupportedStatus)();
            if ( !Get.handleSupportedCodes(supported, context,
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
                    case Got:
                        context.shared_working.result =
                            SharedWorking.Result.Got;

                        // Receive record value from node.
                        conn.receive(
                            ( in void[] const_payload )
                            {
                                Const!(void)[] payload = const_payload;
                                auto value =
                                    conn.message_parser.getArray!(void)(payload);

                                Notification n;
                                n.received = RequestDataInfo(context.request_id,
                                    value);
                                Get.notify(context.user_params, n);
                            }
                        );
                        return false;

                    case NoRecord:
                        context.shared_working.result =
                            SharedWorking.Result.NoRecord;
                        return true;

                    case WrongNode:
                        context.shared_working.result =
                            SharedWorking.Result.Error;

                        // The node is not reponsible for the key. Notify the user.
                        Notification n;
                        n.wrong_node = RequestNodeInfo(context.request_id,conn.remote_address);
                        Get.notify(context.user_params, n);
                        return false;

                    case Error:
                        context.shared_working.result =
                            SharedWorking.Result.Error;

                        // The node returned an error code. Notify the user.
                        Notification n;
                        n.node_error = RequestNodeInfo(context.request_id,
                            conn.remote_address);
                        Get.notify(context.user_params, n);
                        return false;

                    default:
                        log.warn("Received unknown message code {} from node "
                            ~ "in response to Get request. Treating as "
                            ~ "Error.", result);
                        goto case Error;
                }
            }

            assert(false);
        }
        catch ( RequestOnConn.AbortException e )
        {
            context.shared_working.result = SharedWorking.Result.Timeout;
            throw e;
        }
        catch ( IOError e )
        {
            context.shared_working.result = SharedWorking.Result.Error;

            // A connection error occurred. Notify the user.
            auto info = RequestNodeExceptionInfo(context.request_id,
                conn.remote_address, e);

            Notification n;
            n.node_disconnected = info;
            Get.notify(context.user_params, n);

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
        auto context = Get.getContext(context_blob);

        Notification n;

        with ( SharedWorking.Result ) switch ( context.shared_working.result )
        {
            case NoRecord:
                n.no_record = RequestInfo(context.request_id);
                break;
            case Timeout:
                n.timed_out = RequestInfo(context.request_id);
                break;
            case NoNode:
                n.no_node = RequestInfo(context.request_id);
                break;
            case Failure:
                n.failure = RequestInfo(context.request_id);
                break;
            case Got:
                // Got notification was already handled in getFromNode(), where
                // the value received from the node is available.
            case Error:
                // Error notification was already handled in getFromNode(),
                // where we have access to the node's address &/ exception.
                return;
            default:
                assert(false);
        }

        Get.notify(context.user_params, n);
    }
}
