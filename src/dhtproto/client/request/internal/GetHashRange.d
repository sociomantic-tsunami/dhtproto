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
    import swarm.neo.client.RequestOnConn;
    import swarm.neo.client.mixins.RequestCore;
    import swarm.neo.client.mixins.AllNodesRequestCore;
    import swarm.neo.client.Connection;

    import dhtproto.client.internal.SharedResources;

    import ocean.io.select.protocol.generic.ErrnoIOException: IOError;

    /***************************************************************************

        Data which the request needs while it is progress. An instance of this
        struct is stored in the request's context (which is passed to the
        request handler).

    ***************************************************************************/

    private static struct SharedWorking
    {
        /// Shared working data required for core all-nodes request behaviour.
        AllNodesRequestSharedWorkingData all_nodes;
    }

    /***************************************************************************

        Request core. Mixes in the types `NotificationInfo`, `Notifier`,
        `Params`, `Context` plus the static constants `request_type` and
        `request_code`.

    ***************************************************************************/

    mixin RequestCore!(RequestType.AllNodes, RequestCode.GetHashRange, 0,
        Args, SharedWorking, Notification);

    /***************************************************************************

        Request handler. Called from RequestOnConn.runHandler(). Never exits:
        this request must remain active during the client's whole lifetime.

        Params:
            conn = connection event dispatcher
            context_blob = untyped chunk of data containing the serialized
                context of the request which is to be handled

    ***************************************************************************/

    public static void handler ( RequestOnConn.EventDispatcherAllNodes conn,
        void[] context_blob )
    out
    {
        assert(false);
    }
    body
    {
        auto context = GetHashRange.getContext(context_blob);

        auto shared_resources = SharedResources.fromObject(
            context.shared_resources);
        scope handler = new GetHashRangeHandler(conn, context,
            shared_resources);
        handler.run();
    }

    /***************************************************************************

        Request finished notifier. Called from Request.handlerFinished(). Under
        normal circumstances, this will never happen.

        Params:
            context_blob = untyped chunk of data containing the serialized
                context of the request which is finishing

    ***************************************************************************/

    public static void all_finished_notifier ( void[] context_blob )
    {
        log.error("GetHashRange request finished. This should never happen :(");
    }
}

/*******************************************************************************

    GetHashRange handler class instantiated inside the main handler() function,
    above.

*******************************************************************************/

private scope class GetHashRangeHandler
{
    import swarm.neo.request.Command;
    import swarm.neo.client.Connection;
    import swarm.neo.client.RequestOnConn;
    import swarm.neo.connection.RequestOnConnBase;
    import swarm.neo.client.mixins.AllNodesRequestCore;
    import swarm.neo.request.RequestEventDispatcher;
    import swarm.neo.AddrPort;

    import dhtproto.common.GetHashRange;
    import dhtproto.client.internal.SharedResources;

    /// Request-on-conn event dispatcher.
    private RequestOnConn.EventDispatcherAllNodes conn;

    /// Request context.
    private GetHashRange.Context* context;

    /// Client shared resources. (Note that, unlike many requests, this is not
    /// a resource acquirer. This request does not acquire any resources.)
    private SharedResources resources;

    /***************************************************************************

        Constructor.

        Params:
            conn = request-on-conn event dispatcher to communicate with node
            context = deserialised request context
            resources = client shared resources

    ***************************************************************************/

    public this ( RequestOnConn.EventDispatcherAllNodes conn,
        GetHashRange.Context* context, SharedResources resources )
    {
        this.conn = conn;
        this.context = context;
        this.resources = resources;
    }

    /***************************************************************************

        Main request handling entry point.

    ***************************************************************************/

    public void run ( )
    {
        auto initialiser = createAllNodesRequestInitialiser!(GetHashRange)(
            this.conn, this.context, &this.fillPayload);
        auto request = createAllNodesRequest!(GetHashRange)(this.conn,
            this.context, &this.connect, &this.disconnected, initialiser,
            &this.handle);
        request.run();
    }

    /***************************************************************************

        Connect policy, called from AllNodesRequest template to ensure the
        connection to the node is up.

        Returns:
            true to continue handling the request; false to abort

    ***************************************************************************/

    private bool connect ( )
    {
        return allNodesRequestConnector(this.conn);
    }

    /***************************************************************************

        Disconnected policy, called from AllNodesRequest template when an I/O
        error occurs on the connection.

        Params:
            e = exception indicating error which occurred on the connection

    ***************************************************************************/

    private void disconnected ( Exception e )
    {
        // Log errors, except when the connection was deliberately shut down.
        if ( cast(Connection.ConnectionClosedException)e is null )
            log.error("I/O error: {} @ {}:{}", e.message, e.file, e.line);
    }

    /***************************************************************************

        FillPayload policy, called from AllNodesRequestInitialiser template
        to add request-specific data to the initial message payload send to the
        node to begin the request.

        Params:
            payload = message payload to be filled

    ***************************************************************************/

    private void fillPayload ( RequestOnConnBase.EventDispatcher.Payload payload )
    {
        // Nothing more to add. (Request code and version already added.)
    }

    /***************************************************************************

        Handler policy, called from AllNodesRequest template to run the
        request's main handling logic.

    ***************************************************************************/

    private void handle ( )
    {
        // Receive and store node's current hash range
        hash_t min, max;
        this.conn.receive(
            ( in void[] payload )
            {
                Const!(void)[] payload_slice = payload;
                min = *this.conn.message_parser.getValue!(hash_t)(payload_slice);
                max = *this.conn.message_parser.getValue!(hash_t)(payload_slice);
            }
        );
        this.resources.node_hash_ranges.updateNodeHashRange(
            this.conn.remote_address, min, max);

        while ( true )
        {
            this.conn.receive(
                ( in void[] payload )
                {
                    Const!(void)[] payload_slice = payload;
                    auto msg_type = *this.conn.message_parser.
                        getValue!(MessageType)(payload_slice);

                    with ( MessageType ) switch ( msg_type )
                    {
                        case NewNode:
                            typeof(AddrPort.naddress) addr;
                            typeof(AddrPort.nport) port;
                            hash_t min, max;
                            this.conn.message_parser.parseBody(payload_slice,
                                addr, port, min, max);

                            this.resources.node_hash_ranges.updateNodeHashRange(
                                AddrPort(addr, port), min, max);
                            break;

                        case ChangeHashRange:
                            hash_t new_min, new_max;
                            this.conn.message_parser.parseBody(payload_slice,
                                new_min, new_max);

                            this.resources.node_hash_ranges.updateNodeHashRange(
                                this.conn.remote_address, new_min, new_max);
                            break;

                        default:
                            log.error("Unknown message code {} received", msg_type);
                            throw this.conn.shutdownWithProtocolError(
                                "Message parsing error");
                    }
                }
            );
        }
    }
}
