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
        import ocean.core.array.Mutation : copy;
        import ocean.core.array.Search : contains;
        import swarm.neo.util.VoidBufferAsArrayOf;

        /// Shared working data required for core all-nodes request behaviour.
        AllNodesRequestSharedWorkingData all_nodes;

        /// Pointer to a list of the channel names that the client has already
        /// been notified of.
        VoidBufferAsArrayOf!(void[]) notified_channels;

        /***********************************************************************

            Informs the caller whether the user should be notified about the
            specified channel name, ensuring that the user is told about each
            channel only once.

            Params:
                channel = name of the channel
                resources = request resource acquirer

            Returns:
                true if the notifier should be called

        ***********************************************************************/

        bool shouldNotifyChannel ( Const!(void)[] channel,
            SharedResources.RequestResources resources )
        {
            bool already_notified = false;

            // Acquire the array of channel name slices that is shared by all
            // RoCs, if it's not already acquired.
            if ( this.notified_channels == typeof(this.notified_channels).init )
                this.notified_channels = resources.getBufferList();
            else
                already_notified =
                    (this.notified_channels.array().contains(channel) == true);

            // If this channel name has not been seen before, copy it into a new
            // buffer and add a slice to that buffer to the array of channel
            // name slices (this.notified_channels).
            if ( !already_notified )
            {
                auto buf = resources.getVoidBuffer();
                auto void_channel = cast(void[])channel;
                (*buf).copy(void_channel);
                this.notified_channels ~= cast(char[])(*buf);
            }

            return !already_notified;
        }
    }

    /***************************************************************************

        Request core. Mixes in the types `NotificationInfo`, `Notifier`,
        `Params`, `Context` plus the static constants `request_type` and
        `request_code`.

    ***************************************************************************/

    mixin RequestCore!(RequestType.AllNodes, RequestCode.GetChannels, 0, Args,
        SharedWorking, Notification);

    /***************************************************************************

        Request handler. Called from RequestOnConn.runHandler().

        Params:
            conn = request-on-conn event dispatcher
            context_blob = untyped chunk of data containing the serialized
                context of the request which is to be handled

    ***************************************************************************/

    public static void handler ( RequestOnConn.EventDispatcherAllNodes conn,
        void[] context_blob )
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

    ***************************************************************************/

    public static void all_finished_notifier ( void[] context_blob )
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
    import swarm.neo.request.Command;

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
            this.conn, this.context, &this.fillPayload);
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
        // Notify the user of the disconnection.
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

                if ( this.context.shared_working.shouldNotifyChannel(channel,
                    this.resources) )
                {
                    Notification notification;
                    notification.received =
                        RequestDataInfo(context.request_id, channel);
                    GetChannels.notify(this.context.user_params, notification);
                }
                break;

            case Error:
                // The node returned an error code. Notify the user and
                // end the request.
                GetChannels.Notification n;
                n.node_error = RequestNodeInfo(
                    this.context.request_id, this.conn.remote_address);
                GetChannels.notify(this.context.user_params, n);
                return true;

            case Finished:
                return true;

            default:
                assert(false);
        }

        return false;
    }
}
