/*******************************************************************************

    Client DHT GetHashRange v0 request handler.

    Note that this request is unusual in that there is no public API. It is not
    possible for the user of the DHT client to assign this request; it is only
    ever assigned internally by the client itself (upon construction).

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.internal.GetHashRange;

import ocean.transition;
import ocean.util.log.Logger;
import dhtproto.common.GetHashRange;
import swarm.neo.client.NotifierTypes;

/*******************************************************************************

    Module logger

*******************************************************************************/

static private Logger log;
static this ( )
{
    log = Log.lookup("dhtproto.client.request.internal.GetHashRange");
}

/*******************************************************************************

    Request-specific arguments provided by the user and passed to the notifier.

*******************************************************************************/

private struct Args
{
    // Dummy (not required by this request)
}

/*******************************************************************************

    Notification smart union (never used, but required by RequestCore).

*******************************************************************************/

private struct Notification
{
    /// The request was tried on a node and failed because it is unsupported;
    /// it will be retried on any remaining nodes. (Required by RequestCore.)
    RequestNodeUnsupportedInfo unsupported;
}

/*******************************************************************************

    Type of notifcation delegate (never used, but required by RequestCore).

*******************************************************************************/

private alias void delegate ( Notification, Args ) Notifier;

/*******************************************************************************

    GetHashRange request implementation.

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

public struct GetHashRange
{
    import dhtproto.common.RequestCodes;
    import swarm.neo.client.mixins.RequestCore;
    import swarm.neo.client.Connection;

    import ocean.io.select.protocol.generic.ErrnoIOException: IOError;

    /***************************************************************************

        Data which the request needs while it is progress. An instance of this
        struct is stored in the request's context (which is passed to the
        request handler).

    ***************************************************************************/

    private static struct SharedWorking
    {
        // Dummy (not required by this request)
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

    mixin RequestCore!(RequestType.AllNodes, RequestCode.GetHashRange, 0,
        Args, SharedWorking, Working, Notification);

    /***************************************************************************

        Request handler. Called from RequestOnConn.runHandler(). Never exits:
        this request must remain active during the client's whole lifetime.

        Params:
            conn = connection event dispatcher
            context_blob = untyped chunk of data containing the serialized
                context of the request which is to be handled
            working_blob = untyped chunk of data containing the serialized
                working data for the request on this connection

    ***************************************************************************/

    public static void handler ( RequestOnConn.EventDispatcherAllNodes conn,
        void[] context_blob, void[] working_blob )
    out
    {
        assert(false);
    }
    body
    {
        scope h = new Handler(conn, context_blob);

        do
        {
            try
            {
                h.run(h.State.EstablishingConnection);
            }
            // As this request is fundamental to the DHT client, we always
            // retry after errors.
            catch (IOError e)
            {
                log.error("I/O error: {} @ {}:{}", getMsg(e), e.file, e.line);
            }
            catch (Connection.ConnectionClosedException e)
            {
                // Connection deliberately shut down -- no need to log.
            }
            catch (Exception e)
            {
                log.error("{} error: {} @ {}:{}", e.classinfo.name,
                    getMsg(e), e.file, e.line);
            }
        }
        while ( true ); // always try again
    }

    /***************************************************************************

        Request finished notifier. Called from Request.handlerFinished(). Under
        normal circumstances, this will never happen.

        Params:
            context_blob = untyped chunk of data containing the serialized
                context of the request which is finishing
            working_data_iter = iterator over the stored working data associated
                with each connection on which this request was run

    ***************************************************************************/

    public static void all_finished_notifier ( void[] context_blob,
        IRequestWorkingData working_data_iter )
    {
        log.error("GetHashRange request finished. This should never happen :(");
    }
}

/*******************************************************************************

    GetHashRange handler class instantiated inside the main handler() function,
    above.

*******************************************************************************/

private scope class Handler
{
    import swarm.neo.util.StateMachine;
    import swarm.neo.request.Command : StatusCode, SupportedStatus;
    import swarm.neo.AddrPort;
    import swarm.neo.client.RequestOnConn;
    import dhtproto.common.RequestCodes;
    import dhtproto.client.internal.SharedResources;

    /***************************************************************************

        Mixin core of state machine.

    ***************************************************************************/

    mixin(genStateMachine([
        "EstablishingConnection",
        "Initialising",
        "Receiving"
    ]));

    /***************************************************************************

        Event dispatcher for this connection.

    ***************************************************************************/

    private RequestOnConn.EventDispatcherAllNodes conn;

    /***************************************************************************

        Deserialized request context. Empty, but has methods which are used.

    ***************************************************************************/

    public GetHashRange.Context* context;

    /***************************************************************************

        Constructor.

        Params:
            conn = Event dispatcher for this connection
            context_blob = serialized request context

    ***************************************************************************/

    public this ( RequestOnConn.EventDispatcherAllNodes conn,
                  void[] context_blob )
    {
        this.conn = conn;
        this.context = GetHashRange.getContext(context_blob);
    }

    /***************************************************************************

        Waits for the connection to be established if it is down.

        Next state:
            - Initialising (once connection is established)

        Returns:
            next state

    ***************************************************************************/

    private State stateEstablishingConnection ( )
    {
        while (true)
        {
            switch (this.conn.waitForReconnect())
            {
                case conn.FiberResumeCodeReconnected:
                case 0: // The connection is already up
                    return State.Initialising;

                default:
                    assert(false,
                        typeof(this).stringof ~ ".stateWaitingForReconnect: " ~
                        "Unexpected fiber resume code when reconnecting");
            }
        }
    }

    /***************************************************************************

        Sends the request code, version, etc. to the node to begin the request,
        then receives the status code and hash range from the node.

        Next state:
            - Receiving (once the request is initialised)
            - Exit, if the node returns an error status

        Returns:
            next state

    ***************************************************************************/

    private State stateInitialising ( )
    in
    {
        // stateWaitingForReconnect should guarantee we're already connected
        assert(this.conn.waitForReconnect() == 0);
    }
    body
    {
        // Send request info to node
        this.conn.send(
            ( conn.Payload payload )
            {
                payload.add(GetHashRange.cmd.code);
                payload.add(GetHashRange.cmd.ver);
            }
        );
        this.conn.flush();

        // Receive status from node and stop the request if not Ok
        auto status = conn.receiveValue!(StatusCode)();
        switch ( status )
        {
            case RequestStatusCode.Started:
                break;

            case SupportedStatus.RequestNotSupported:
                log.error("Node {}:{} returned a request not supported status to GetHashRange",
                    this.conn.remote_address.address_bytes,
                    this.conn.remote_address.port);
                return State.Exit;

            case SupportedStatus.RequestVersionNotSupported:
                log.error("Node {}:{} returned a request version not supported status to GetHashRange",
                    this.conn.remote_address.address_bytes,
                    this.conn.remote_address.port);
                return State.Exit;

            case RequestStatusCode.Error:
                log.error("Node {}:{} returned an error status to GetHashRange",
                    this.conn.remote_address.address_bytes,
                    this.conn.remote_address.port);
                return State.Exit;

            default:
                log.error("Node {}:{} returned an unknown status code {} to GetHashRange",
                    this.conn.remote_address.address_bytes,
                    this.conn.remote_address.port, status);
                return State.Exit;
        }

        // Receive and store node's current hash range
        hash_t min, max;
        this.conn.receive(
            ( in void[] const_payload )
            {
                Const!(void)[] payload = const_payload;
                min = *this.conn.message_parser.getValue!(hash_t)(payload);
                max = *this.conn.message_parser.getValue!(hash_t)(payload);
            }
        );
        auto shared_resources = SharedResources.fromObject(
            this.context.shared_resources);
        shared_resources.node_hash_ranges.updateNodeHashRange(
            this.conn.remote_address, min, max);

        return State.Receiving;
    }

    /***************************************************************************

        Default running state. Receives and handles hash-range update messages
        from the node.

        Next state:
            - Receiving again

        Returns:
            next state

    ***************************************************************************/

    private State stateReceiving ( )
    {
        bool msg_error;
        this.conn.receive(
            ( in void[] const_payload )
            {
                Const!(void)[] payload = const_payload;

                auto msg_type =
                    *this.conn.message_parser.getValue!(MessageType)(payload);

                with ( MessageType ) switch ( msg_type )
                {
                    case NewNode:
                        typeof(AddrPort.naddress) addr;
                        typeof(AddrPort.nport) port;
                        hash_t min, max;
                        this.conn.message_parser.parseBody(payload,
                            addr, port, min, max);

                        auto shared_resources = SharedResources.fromObject(
                            this.context.shared_resources);
                        shared_resources.node_hash_ranges.updateNodeHashRange(
                            AddrPort(addr, port), min, max);
                        break;

                    case ChangeHashRange:
                        hash_t new_min, new_max;
                        this.conn.message_parser.parseBody(payload,
                            new_min, new_max);

                        auto shared_resources = SharedResources.fromObject(
                            this.context.shared_resources);
                        shared_resources.node_hash_ranges.updateNodeHashRange(
                            this.conn.remote_address, new_min, new_max);
                        break;

                    default:
                        log.error("Unknown message code {} received", msg_type);
                        this.conn.shutdownWithProtocolError("Message parsing error");
                }
            }
        );

        return State.Receiving;
    }
}
