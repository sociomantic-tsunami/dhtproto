/*******************************************************************************

    Client DHT RemoveChannel v0 request handler.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.internal.RemoveChannel;

import ocean.transition;
import ocean.util.log.Logger;

/*******************************************************************************

    RemoveChannel request implementation.

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

public struct RemoveChannel
{
    import dhtproto.common.RemoveChannel;
    import dhtproto.client.request.RemoveChannel;
    import dhtproto.common.RequestCodes;
    import dhtproto.client.NotifierTypes;
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

        /// Flag indicating that one or more request-on-conns prevented the
        /// request from being handled due to the wrong client permissions.
        bool not_permitted;
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

    mixin RequestCore!(RequestType.AllNodes, RequestCode.RemoveChannel, 0, Args,
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
        auto context = RemoveChannel.getContext(context_blob);

        auto shared_resources = SharedResources.fromObject(
            context.shared_resources);
        scope acquired_resources = shared_resources.new RequestResources;

        scope handler = new RemoveChannelHandler(conn, context,
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
        auto context = RemoveChannel.getContext(context_blob);
        Notification n;

        // Different nodes may have returned different status codes.
        if ( context.shared_working.not_permitted )
            n.not_permitted = RequestInfo(context.request_id);
        else
            n.finished = RequestInfo(context.request_id);

        RemoveChannel.notify(context.user_params, n);
    }
}

/*******************************************************************************

    Client RemoveChannel v0 request handler.

*******************************************************************************/

private scope class RemoveChannelHandler
{
    import swarm.neo.client.RequestOnConn;
    import swarm.neo.connection.RequestOnConnBase;
    import swarm.neo.client.mixins.AllNodesRequestCore;
    import swarm.neo.request.Command;

    import dhtproto.common.RemoveChannel;
    import dhtproto.client.request.RemoveChannel;
    import dhtproto.client.internal.SharedResources;

    /// Request-on-conn event dispatcher.
    private RequestOnConn.EventDispatcherAllNodes conn;

    /// Request context.
    private RemoveChannel.Context* context;

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
        RemoveChannel.Context* context, SharedResources.RequestResources resources )
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
        auto initialiser = createAllNodesRequestInitialiser!(RemoveChannel)(
            this.conn, this.context, &this.fillPayload, &this.handleSupportedCode);
        auto request = createAllNodesRequest!(RemoveChannel)(this.conn, this.context,
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
        // Notify the user of the disconnection.
        RemoveChannel.Notification notification;
        notification.node_disconnected =
            RequestNodeExceptionInfo(this.context.request_id,
            this.conn.remote_address, e);
        RemoveChannel.notify(this.context.user_params, notification);
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
        payload.addArray(this.context.user_params.args.channel);
    }

    /***************************************************************************

        HandleStatusCode policy, called from AllNodesRequestInitialiser
        template to decide how to handle the status code received from the node.

        Params:
            supported = supported code received from the node in response to the
                initial message

        Returns:
            true to continue handling the request (supported); false to abort
            (unsupported)

    ***************************************************************************/

    private bool handleSupportedCode ( ubyte code )
    {
        auto supported = cast(SupportedStatus)code;
        return RemoveChannel.handleSupportedCodes(supported,
            this.context, this.conn.remote_address);
    }

    /***************************************************************************

        Handler policy, called from AllNodesRequest template to run the
        request's main handling logic.

    ***************************************************************************/

    private void handle ( )
    {
        auto result = conn.receiveValue!(MessageType)();

        with ( MessageType ) switch ( result )
        {
            case ChannelRemoved:
                // Request succeeded.
                break;

            case NotPermitted:
                // The client is not "admin" and may not remove channels.
                this.context.shared_working.not_permitted = true;
                break;

            case Error:
                // The node returned an error code.
                RemoveChannel.Notification n;
                n.node_error = RequestNodeInfo(
                    this.context.request_id, conn.remote_address);
                RemoveChannel.notify(this.context.user_params, n);
                break;

            default:
                // Treat unknown codes as internal errors.
                goto case Error;
        }
    }
}
