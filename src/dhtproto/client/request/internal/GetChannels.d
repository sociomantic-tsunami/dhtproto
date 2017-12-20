/*******************************************************************************

    Client DHT GetChannels v0 request handler.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.internal.GetChannels;

import ocean.transition;
import ocean.util.log.Logger;

/*******************************************************************************

    GetChannels request implementation.

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

public struct GetChannels
{
    import dhtproto.common.GetChannels;
    import dhtproto.client.request.GetChannels;
    import dhtproto.common.RequestCodes;
    import dhtproto.client.NotifierTypes;
    import swarm.util.RecordBatcher;
    import swarm.neo.client.mixins.RequestCore;
    import swarm.neo.client.mixins.AllNodesRequestCore;
    import swarm.neo.client.RequestHandlers;
    import swarm.neo.client.RequestOnConn;
    import dhtproto.client.internal.SharedResources;

    import ocean.io.select.protocol.generic.ErrnoIOException: IOError;

    /***************************************************************************

        Data which the request needs while it is progress. An instance of this
        struct is stored per connection on which the request runs and is passed
        to the request handler.

    ***************************************************************************/

    private static struct SharedWorking
    {
        /// Shared working data required for core all-nodes request behaviour.
        AllNodesRequestSharedWorkingData all_nodes;
    }

    /***************************************************************************

        Data which each request-on-conn needs while it is progress. An instance
        of this struct is stored per connection on which the request runs and is
        passed to the request handler.

    ***************************************************************************/

    private static struct Working
    {
        // Dummy struct.
    }

    /***************************************************************************

        Request core. Mixes in the types `NotificationInfo`, `Notifier`,
        `Params`, `Context` plus the static constants `request_type` and
        `request_code`.

    ***************************************************************************/

    mixin RequestCore!(RequestType.AllNodes, RequestCode.GetChannels, 0, Args,
        SharedWorking, Working, Notification);

    /***************************************************************************

        Request handler. Called from RequestOnConn.runHandler().

        Params:
            conn = request-on-conn event dispatcher
            context_blob = untyped chunk of data containing the serialized
                context of the request which is to be handled
            working_blob = untyped chunk of data containing the serialized
                working data for the request on this connection

    ***************************************************************************/

    public static void handler ( RequestOnConn.EventDispatcherAllNodes conn,
        void[] context_blob, void[] working_blob )
    {
        auto context = GetChannels.getContext(context_blob);

        auto shared_resources = SharedResources.fromObject(
            context.shared_resources);
        scope acquired_resources = shared_resources.new RequestResources;

        scope handler = new GetChannelsHandler(conn, context,
            acquired_resources);
        handler.run();
    }

    /***************************************************************************

        Request finished notifier. Called from Request.handlerFinished().

        Params:
            context_blob = untyped chunk of data containing the serialized
                context of the request which is finishing
            working_data_iter = iterator over the stored working data associated
                with each connection on which this request was run

    ***************************************************************************/

    public static void all_finished_notifier ( void[] context_blob,
        IRequestWorkingData working_data_iter )
    {
        auto context = GetChannels.getContext(context_blob);

        Notification n;
        n.finished = RequestInfo(context.request_id);
        GetChannels.notify(context.user_params, n);
    }
}

/*******************************************************************************

    Client GetChannels v0 request handler.

*******************************************************************************/

private scope class GetChannelsHandler
{
    import swarm.neo.client.RequestOnConn;
    import swarm.neo.connection.RequestOnConnBase;
    import swarm.neo.client.mixins.AllNodesRequestCore;
    import swarm.neo.request.RequestEventDispatcher;

    import dhtproto.common.GetChannels;
    import dhtproto.client.request.GetChannels;
    import dhtproto.client.internal.SharedResources;

    /// Request-on-conn event dispatcher.
    private RequestOnConn.EventDispatcherAllNodes conn;

    /// Request context.
    private GetChannels.Context* context;

    /// Request resource acquirer.
    private SharedResources.RequestResources resources;

    /***************************************************************************

        Constructor.

        Params:
            conn = request-on-conn event dispatcher to communicate with node
            context = deserialised request context
            resources = request resource acquirer

    ***************************************************************************/

    public this ( RequestOnConn.EventDispatcherAllNodes conn,
        GetChannels.Context* context, SharedResources.RequestResources resources )
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
        auto initialiser = createAllNodesRequestInitialiser!(GetChannels)(
            this.conn, this.context, &this.fillPayload, &this.handleStatusCode);
        auto request = createAllNodesRequest!(GetChannels)(this.conn, this.context,
            &this.connect, &this.disconnected, initialiser, &this.handle);
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
        // Notify the user of the disconnection. The user may use the
        // controller, at this point, but as the request is not active
        // on this connection, no special behaviour is needed.
        GetChannels.Notification notification;
        notification.node_disconnected =
            RequestNodeExceptionInfo(this.context.request_id,
            this.conn.remote_address, e);
        GetChannels.notify(this.context.user_params, notification);
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

        HandleStatusCode policy, called from AllNodesRequestInitialiser
        template to decide how to handle the status code received from the node.

        Params:
            status = status code received from the node in response to the
                initial message

        Returns:
            true to continue handling the request (OK status); false to abort
            (error status)

    ***************************************************************************/

    private bool handleStatusCode ( ubyte status )
    {
        auto getchannels_status = cast(RequestStatusCode)status;

        if ( GetChannels.handleGlobalStatusCodes(getchannels_status,
            this.context, this.conn.remote_address) )
        {
            return false; // Global code, e.g. request/version not supported
        }

        // GetChannels-specific codes
        with ( RequestStatusCode ) switch ( getchannels_status )
        {
            case Started:
                // Expected "request started" code
                return true;

            case Error:
                // The node returned an error code. Notify the user and
                // end the request.
                GetChannels.Notification n;
                n.node_error = RequestNodeInfo(
                    this.context.request_id, conn.remote_address);
                GetChannels.notify(this.context.user_params, n);
                return false;

            default:
                // Treat unknown codes as internal errors.
                goto case Error;
        }

        assert(false);
    }

    /***************************************************************************

        Handler policy, called from AllNodesRequest template to run the
        request's main handling logic.

    ***************************************************************************/

    private void handle ( )
    {
        // Receive the incoming record stream.
        bool finished;
        do
        {
            this.conn.receive(
                ( in void[] payload )
                {
                    finished = this.handleMessage(payload);
                }
            );
        }
        while ( !finished );
    }

    /***************************************************************************

        Handles a single message received from the node.

        Params:
            payload = message payload

        Returns:
            true if the message indicates that the request is finished

    ***************************************************************************/

    private bool handleMessage ( Const!(void)[] payload )
    {
        auto msg_type =
            *this.conn.message_parser.getValue!(MessageType)(payload);
        with ( MessageType ) switch ( msg_type )
        {
            case ChannelName:
                Const!(void)[] channel;
                this.conn.message_parser.parseBody(payload, channel);
                Notification notification;
                notification.received =
                    RequestDataInfo(context.request_id, channel);
                GetChannels.notify(this.context.user_params, notification);
                break;

            case Finished:
                return true;

            default:
                assert(false);
        }

        return false;
    }
}
