/*******************************************************************************

    Client DHT Update v0 request handler.

    Copyright:
        Copyright (c) 2018 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.internal.Update;

import ocean.transition;
import ocean.core.VersionCheck;
import ocean.util.log.Logger;
import ocean.core.Verify;

/*******************************************************************************

    Module logger

*******************************************************************************/

static private Logger log;
static this ( )
{
    log = Log.lookup("dhtproto.client.request.internal.Update");
}

/*******************************************************************************

    Update request implementation.

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

public struct Update
{
    import dhtproto.common.Update;
    import dhtproto.common.RequestCodes;
    import dhtproto.client.request.Update;
    import swarm.neo.AddrPort;
    import swarm.neo.client.mixins.RequestCore;
    import swarm.neo.client.RequestHandlers;
    import swarm.neo.client.RequestOnConn;

    /***************************************************************************

        Data which the request needs while it is progress. An instance of this
        struct is stored per connection on which the request runs and is passed
        to the request handler.

    ***************************************************************************/

    private static struct SharedWorking
    {
        /// Address of the second node to contact, in the case where the record
        /// is written back to a different node than the one it was read from.
        AddrPort second_node_addr;

        /// Flag indicating whether the communication with the second node
        /// succeeded or not.
        bool second_node_failed;

        /// Reference to the original request-on-conn that handles reading the
        /// record to be updated. Stored so that it can be resumed from the
        /// second request-on-conn (if required).
        RequestOnConn.EventDispatcher first_request_on_conn;

        /// Hash of the record value fetched from the node. Sent back to the
        /// node along with the updated value. Used to confirm that no other
        /// client has modified the value in the meantime.
        hash_t original_hash;

        /// Updated record value.
        void[]* updated_value;

        /// Enum indicating the ways in which the request may end.
        public enum Result
        {
            Error,      // Default value; client / I/O / node error
            Succeeded,  // Request succeeded.
            Conflict,   // Another client updated the record.
            NoRecord,   // Succeeded, but record not in DHT.
            NoNode      // No node responsible for key
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

    mixin RequestCore!(RequestType.MultiNode, RequestCode.Update, 0, Args,
        SharedWorking, Notification);

    /// Fiber resume code.
    enum SecondROCFinished = 1;

    /***************************************************************************

        Request handler. Called from RequestOnConn.runHandler().

        FIXME: Note that the logic for retrying the request on other nodes which
        previously covered the hash has not been properly tested. This will
        require a full neo implementation of the Redistribute request. See
        https://github.com/sociomantic-tsunami/dhtnode/issues/21

        Params:
            use_node = delegate to be called from the handler to get access to
                an `EventDispatcher` instance to communicate with the specified
                node
            new_request_on_conn = delegate to be called from the handler to
                cause the handler to be called again in a new `RequestOnConn
                instance
            context_blob = packed request context struct

    ***************************************************************************/

    public static void handler ( UseNodeDg use_node,
        scope NewRequestOnConnDg new_request_on_conn, void[] context_blob )
    {
        auto context = Update.getContext(context_blob);
        context.shared_working.result = SharedWorking.Result.Error;

        // The logic to perform here depends which RoC we're running in.
        if ( context.shared_working.first_request_on_conn is null )
        {
            auto handler =
                FirstROCHandler(use_node, new_request_on_conn, context);
            handler.handle();
        }
        else
        {
            // Whatever happens when communicating with the second node, we must
            // always resume the first request-on-conn so that the request can
            // finish cleanly.
            scope ( exit )
            {
                context.shared_working.first_request_on_conn.resumeFiber(
                    Update.SecondROCFinished);
            }

            auto handler = SecondROCHandler(use_node, context);
            handler.handle();
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
        auto context = Update.getContext(context_blob);

        Notification n;
        auto info = RequestInfo(context.request_id);

        with ( SharedWorking.Result ) switch ( context.shared_working.result )
        {
            case Succeeded:
                n.succeeded = info;
                break;
            case NoRecord:
                n.no_record = info;
                break;
            case Conflict:
                n.conflict = info;
                break;
            case NoNode:
                n.no_node = info;
                break;
            case Error:
                n.error = info;
                return;
            default:
                assert(false);
        }

        Update.notify(context.user_params, n);
    }
}

/// Handler for the initial request-on-conn (which reads the record value from
/// the DHT).
private struct FirstROCHandler
{
    import ocean.io.digest.Fnv1;
    import ocean.io.select.protocol.generic.ErrnoIOException: IOError;
    import swarm.neo.AddrPort;
    import swarm.neo.client.NotifierTypes;
    import swarm.neo.client.RequestHandlers;
    import swarm.neo.client.RequestOnConn;
    import swarm.neo.request.Command;
    import dhtproto.client.NotifierTypes;
    import dhtproto.client.internal.NodeHashRanges;
    import dhtproto.client.internal.SharedResources;
    import dhtproto.common.Update;

    /// Enum defining three-state return values of some methods.
    private enum Action
    {
        Abort, // An error occurred and the request should be aborted.
        Retry, // The operation failed, but can be retried (on another node).
        Success // The operation succeeded.
    }

    /// Delegate to get access to an event dispatcher for a specific connection.
    private UseNodeDg use_node;

    /// Delegate to spawn a new request-on-conn. When spawned, Update.handle
    /// will be called in the new RoC fiber.
    private NewRequestOnConnDg new_request_on_conn;

    /// Serialised request context.
    private Update.Context* context;

    /***************************************************************************

        Entry point for the first RoC's logic.

    ***************************************************************************/

    public void handle ( )
    {
        auto shared_resources = SharedResources.fromObject(
            this.context.shared_resources);
        scope acquired_resources = shared_resources.new RequestResources;

        // Get the list of nodes reponsible for this hash.
        auto nodes = shared_resources.node_hash_ranges.getNodesForHash(
            this.context.user_params.args.key,
            acquired_resources.getNodeHashRangeBuffer());

        // If no node covers the record's hash, exit.
        if ( nodes.array.length == 0 )
        {
            this.context.shared_working.result =
                Update.SharedWorking.Result.NoNode;
            return;
        }

        // Iterate over the list of responsible nodes, in newest to oldest order
        // of responsibility, trying to get and update the record.
        bool success, error;
        foreach ( node_hash_range; nodes.array() )
        {
            scope conn_dg =
                ( RequestOnConn.EventDispatcher conn )
                {
                    auto ret = this.tryConnection(conn, nodes.array[0].addr,
                        acquired_resources);
                    with ( Action ) final switch ( ret )
                    {
                        case Success:
                            this.context.shared_working.result =
                                Update.SharedWorking.Result.Succeeded;
                            success = true;
                            break;
                        case Abort:
                            // shared_working.result may either be the default
                            // value (Error) or may have been set to a specific
                            // code.
                            error = true;
                            break;
                        case Retry:
                            // No record on this node, retry on the next one.
                            break;
                        version (D_Version2){} else {
                            default: assert(false);
                        }
                    }
                };
            this.use_node(node_hash_range.addr, conn_dg);

            if ( error )
                break;
        }

        // The specified record does not currently exist in the DHT. Do nothing.
        if ( !success && !error )
            this.context.shared_working.result =
                Update.SharedWorking.Result.NoRecord;
    }

    /***************************************************************************

        Tries to do the complete update process, reading from the specified
        node.

        Params:
            conn = connection to communicate over
            newest_responsible_node_addr = address/port of the node that is most
                recently responsible for this record. If a second node must be
                contacted, this is the node that the updated record will be sent
                to
            acquired_resources = request resource acquirer

        Returns:
            Success if updated; Retry if not on this node; Abort on error

    ***************************************************************************/

    private Action tryConnection ( RequestOnConn.EventDispatcher conn,
        AddrPort newest_responsible_node_addr,
        SharedResources.RequestResources acquired_resources )
    {
        try
        {
            // Start the request on this node.
            auto ret = this.queryValueFromNode(conn);
            if ( ret != Action.Success )
                return ret;

            // Receive response (possibly including a record value) from the
            // node.
            ret = Action.Abort;
            conn.receive(
                ( const(void)[] const_payload )
                {
                    ret = this.handleResponse(conn, const_payload,
                        acquired_resources);
                }
            );
            if ( ret != Action.Success )
                return ret;

            // If a value was received, send the updated value to the DHT.
            bool success;
            if ( this.context.shared_working.updated_value !is null )
            {
                if ( conn.remote_address == newest_responsible_node_addr )
                    success = this.updateOnNode(conn);
                else
                    success = this.updateOnDifferentNode(conn,
                        newest_responsible_node_addr);
            }
            // If the user did not provide an updated value, tell the node to
            // leave the record as is.
            else
                success = this.leaveRecordOnNode(conn);

            return success ? Action.Success : Action.Abort;
        }
        catch ( IOError e )
        {
            // Notify user of connection error.
            Update.Notification n;
            n.node_disconnected = RequestNodeExceptionInfo(
                this.context.request_id, conn.remote_address, e);
            Update.notify(this.context.user_params, n);
            return Action.Abort;
        }
    }

    /***************************************************************************

        Asks the node to send the record value; handles the response code.

        Params:
            conn = connection to communicate over

        Returns:
            Success if request supported; Abort on unsupported

    ***************************************************************************/

    private Action queryValueFromNode ( RequestOnConn.EventDispatcher conn )
    {
        // Send request info to node.
        conn.send(
            ( conn.Payload payload )
            {
                payload.add(Update.cmd.code);
                payload.add(Update.cmd.ver);
                payload.addCopy(MessageType.GetRecord);
                payload.addArray(this.context.user_params.args.channel);
                payload.add(this.context.user_params.args.key);
            }
        );

        static if (!hasFeaturesFrom!("swarm", 4, 7))
            conn.flush();

        // Receive supported code from node.
        auto supported = conn.receiveValue!(SupportedStatus)();
        if ( !Update.handleSupportedCodes(supported, this.context,
            conn.remote_address) )
        {
            // Unsupported; abort request.
            return Action.Abort;
        }

        return Action.Success;
    }

    /***************************************************************************

        Reads the response from the node, parses and handles the message type.
        If the message contains a record value, it is passed to the user's
        notification delegate.

        Params:
            conn = connection to communicate over
            const_payload = message payload received from node
            acquired_resources = request resource acquirer

        Returns:
            Success if a value was received; Retry is the record does not exist
            on this node; Abort on error

    ***************************************************************************/

    private Action handleResponse ( RequestOnConn.EventDispatcher conn,
        in void[] const_payload,
        SharedResources.RequestResources acquired_resources )
    {
        Const!(void)[] payload = const_payload;
        auto result = conn.message_parser.getValue!(MessageType)(payload);
        with ( MessageType ) switch ( *result )
        {
            case RecordValue:
                auto value = conn.message_parser.getArray!(void)(payload);

                this.context.shared_working.original_hash = Fnv1a(value);
                verify(this.context.shared_working.updated_value is null);
                this.context.shared_working.updated_value =
                    acquired_resources.getVoidBuffer();

                Update.Notification n;
                n.received = RequestDataUpdateInfo(
                    this.context.request_id, value,
                    this.context.shared_working.updated_value);
                Update.notify(this.context.user_params, n);

                return Action.Success;

            case NoRecord:
                // This node doesn't have the record. Try another.
                return Action.Retry;

            case WrongNode:
                // The node is not reponsible for the key. Notify the user.
                Update.Notification n;
                n.wrong_node = RequestNodeInfo(this.context.request_id,
                    conn.remote_address);
                Update.notify(this.context.user_params, n);
                return Action.Abort;

            case Error:
                // The node returned an error code. Notify the user.
                Update.Notification n;
                n.node_error = RequestNodeInfo(this.context.request_id,
                    conn.remote_address);
                Update.notify(this.context.user_params, n);
                return Action.Abort;

            default:
                log.warn("Received unknown or unexpected message code {} from "
                    ~ "node in response to GetRecord message. Treating as "
                    ~ "Error.", result);
                goto case Error;
        }
    }

    /***************************************************************************

        Sends the node the new record value; handles the response code.

        Params:
            conn = connection to communicate over

        Returns:
            true if the update succeeded, false if there was an error

    ***************************************************************************/

    private bool updateOnNode ( RequestOnConn.EventDispatcher conn )
    {
        // Send updated record to node.
        conn.send(
            ( conn.Payload payload )
            {
                payload.addCopy(MessageType.UpdateRecord);
                payload.add(this.context.shared_working.original_hash);
                payload.addArray(*this.context.shared_working.updated_value);
            }
        );

        static if (!hasFeaturesFrom!("swarm", 4, 7))
            conn.flush();

        // Handle response message.
        auto result = conn.receiveValue!(MessageType)();
        with ( MessageType ) switch ( result )
        {
            case Ok:
                return true;

            case UpdateConflict:
                this.context.shared_working.result =
                    Update.SharedWorking.Result.Conflict;
                return false;

            case Error:
                // The node returned an error code. Notify the user.
                Update.Notification n;
                n.node_error = RequestNodeInfo(this.context.request_id,
                    conn.remote_address);
                Update.notify(this.context.user_params, n);
                return false;

            default:
                log.warn("Received unknown or unexpected message code {} from "
                    ~ "node in response to UpdateRecord message. Treating as "
                    ~ "Error.", result);
                goto case Error;
        }

        assert(false);
    }

    /***************************************************************************

        Starts a new request-on-conn to write the record value to another node.
        Asks the node the record was read from to remove it; handles the
        response code.

        Params:
            conn = connection to communicate with the node that originally had
                the record
            second_node_addr = address/port of the node that the updated record
                will be sent to

        Returns:
            true if the update succeeded, false if there was an error

    ***************************************************************************/

    private bool updateOnDifferentNode ( RequestOnConn.EventDispatcher conn,
        AddrPort second_node_addr )
    {
        this.context.shared_working.first_request_on_conn = conn;
        this.context.shared_working.second_node_addr = second_node_addr;

        // Start a new request-on-conn to write to the other node. This will
        // cause the static `handler()` function to be called again in a new
        // RequestOnConn instance that can be attached to a different
        // connection. The shared working data contains everything the second
        // request-on-conn needs.
        new_request_on_conn();

        // Wait until the second request-on-conn finishes. (This is necessary
        // because this ROC owns the acquired resources tracker, which contains
        // the buffer for the updated value. If this ROC were to simply exit at
        // this stage, this buffer would be relinquished.)
        auto event = conn.nextEvent(conn.NextEventFlags.init);
        verify(event.active == event.Active.resumed);
        verify(event.resumed.code == Update.SecondROCFinished);

        // If the request on the second request-on-conn failed, the result code
        // will already have been set in the shared working data.
        if ( this.context.shared_working.second_node_failed )
            return false;

        // Send message to the node that was read from, informing it that the
        // record was successfully updated on another node and may be deleted.
        conn.send(
            ( conn.Payload payload )
            {
                payload.addCopy(MessageType.RemoveRecord);
            }
        );

        static if (!hasFeaturesFrom!("swarm", 4, 7))
            conn.flush();

        // Handle response message.
        auto result = conn.receiveValue!(MessageType)();
        with ( MessageType ) switch ( result )
        {
            case Ok:
                return true;

            case Error:
                // The node returned an error code. Notify the user.
                Update.Notification n;
                n.node_error = RequestNodeInfo(this.context.request_id,
                    conn.remote_address);
                Update.notify(this.context.user_params, n);
                return false;

            default:
                log.warn("Received unknown or unexpected message code {} from "
                    ~ "node in response to RemoveRecord message. Treating as "
                    ~ "Error.", result);
                goto case Error;
        }

        assert(false);
    }

    /***************************************************************************

        Asks the node the record was read from to leave it; handles the response
        code.

        Params:
            conn = connection to communicate over
            second_node_addr = address/port of the node that the updated record
                will be sent to

        Returns:
            true if the request succeeded, false if there was an error

    ***************************************************************************/

    private bool leaveRecordOnNode ( RequestOnConn.EventDispatcher conn )
    {
        conn.send(
            ( conn.Payload payload )
            {
                payload.addCopy(MessageType.LeaveRecord);
            }
        );

        static if (!hasFeaturesFrom!("swarm", 4, 7))
            conn.flush();

        auto result = conn.receiveValue!(MessageType)();
        with ( MessageType ) switch ( result )
        {
            case Ok:
                return true;

            case Error:
                // The node returned an error code. Notify the user.
                Update.Notification n;
                n.node_error = RequestNodeInfo(this.context.request_id,
                    conn.remote_address);
                Update.notify(this.context.user_params, n);
                return false;

            default:
                log.warn("Received unknown or unexpected message code {} from "
                    ~ "node in response to LeaveRecord message. Treating as "
                    ~ "Error.", result);
                goto case Error;
        }
    }
}

/// Handler for the second request-on-conn (which receives the updated record
/// value, in cases when this is different to the node which it was read from.)
private struct SecondROCHandler
{
    import ocean.io.select.protocol.generic.ErrnoIOException: IOError;
    import swarm.neo.client.NotifierTypes;
    import swarm.neo.client.RequestHandlers;
    import swarm.neo.client.RequestOnConn;
    import swarm.neo.request.Command;
    import dhtproto.common.Update;

    /// Delegate to get access to an event dispatcher for a specific connection.
    private UseNodeDg use_node;

    /// Serialised request context.
    private Update.Context* context;

    /***************************************************************************

        Entry point for the second RoC's logic.

    ***************************************************************************/

    public void handle ( )
    {
        scope conn_dg =
            ( RequestOnConn.EventDispatcher conn )
            {
                if ( !this.handleRequest(conn) )
                    this.context.shared_working.second_node_failed = true;
            };
        this.use_node(this.context.shared_working.second_node_addr, conn_dg);
    }

    /***************************************************************************

        Writes the updated record to the specified node; handles the response
        code.

        Params:
            conn = connection to communicate over

        Returns:
            true if successful, false if node returned an error code

    ***************************************************************************/

    private bool handleRequest ( RequestOnConn.EventDispatcher conn )
    {
        try
        {
            // Send request info to node
            conn.send(
                ( conn.Payload payload )
                {
                    payload.add(Update.cmd.code);
                    payload.add(Update.cmd.ver);
                    payload.addCopy(MessageType.UpdateRecord);
                    payload.addArray(this.context.user_params.args.channel);
                    payload.add(this.context.user_params.args.key);
                    payload.add(this.context.shared_working.original_hash);
                    payload.addArray(*this.context.shared_working.updated_value);
                }
            );

            static if (!hasFeaturesFrom!("swarm", 4, 7))
                conn.flush();

            // Receive supported code from node.
            auto supported = conn.receiveValue!(SupportedStatus)();
            if ( !Update.handleSupportedCodes(supported, this.context,
                conn.remote_address) )
            {
                // Request not supported; abort further handling.
                return false;
            }

            // Handle response message.
            auto result = conn.receiveValue!(MessageType)();
            with ( MessageType ) switch ( result )
            {
                case Ok:
                    return true;

                case UpdateConflict:
                    this.context.shared_working.result =
                        Update.SharedWorking.Result.Conflict;
                    return false;

                case WrongNode:
                    // The node is not reponsible for the key. Notify the user.
                    Update.Notification n;
                    n.wrong_node = RequestNodeInfo(this.context.request_id,
                        conn.remote_address);
                    Update.notify(this.context.user_params, n);
                    return false;

                case Error:
                    // The node returned an error code. Notify the user.
                    Update.Notification n;
                    n.node_error = RequestNodeInfo(this.context.request_id,
                        conn.remote_address);
                    Update.notify(this.context.user_params, n);
                    return false;

                default:
                    log.warn("Received unknown message code {} from node "
                        ~ "in response to Update request. Treating as "
                        ~ "Error.", result);
                    goto case Error;
            }
        }
        catch ( IOError e )
        {
            // Notify user of connection error.
            Update.Notification n;
            n.node_disconnected = RequestNodeExceptionInfo(
                this.context.request_id, conn.remote_address, e);
            Update.notify(this.context.user_params, n);
            return false;
        }

        assert(false);
    }
}
