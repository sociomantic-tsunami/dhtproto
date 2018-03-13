/*******************************************************************************

    Client DHT Mirror v0 request handler.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.internal.Mirror;

import ocean.transition;
import ocean.util.log.Logger;

/*******************************************************************************

    Mirror request implementation.

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

public struct Mirror
{
    import dhtproto.common.Mirror;
    import dhtproto.client.request.Mirror;
    import dhtproto.common.RequestCodes;
    import dhtproto.client.NotifierTypes;
    import swarm.neo.client.mixins.RequestCore;
    import swarm.neo.client.mixins.AllNodesRequestCore;
    import swarm.neo.client.mixins.SuspendableRequestCore;
    import swarm.neo.client.RequestHandlers;
    import swarm.neo.client.RequestOnConn;
    import dhtproto.client.internal.SharedResources;

    import ocean.io.select.protocol.generic.ErrnoIOException: IOError;

    /***************************************************************************

        Request controller, accessible to the user via the client's `control()`
        method.

    ***************************************************************************/

    mixin SuspendableController!(Mirror, IController, MessageType);

    /***************************************************************************

        Data which the request needs while it is progress. An instance of this
        struct is stored per connection on which the request runs and is passed
        to the request handler.

    ***************************************************************************/

    private static struct SharedWorking
    {
        /// Shared working data required for core all-nodes request behaviour.
        AllNodesRequestSharedWorkingData all_nodes;

        /// Shared working data required for core suspendable behaviour.
        SuspendableRequestSharedWorkingData suspendable_control;
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

    mixin RequestCore!(RequestType.AllNodes, RequestCode.Mirror, 0, Args,
        SharedWorking, Working, Notification);

    /***************************************************************************

        Request handler. Called from RequestOnConn.runHandler().

        Params:
            use_node = delegate to get an EventDispatcher for the node with the
                specified address
            context_blob = untyped chunk of data containing the serialized
                context of the request which is to be handled
            working_blob = untyped chunk of data containing the serialized
                working data for the request on this connection

    ***************************************************************************/

    public static void handler ( RequestOnConn.EventDispatcherAllNodes conn,
        void[] context_blob, void[] working_blob )
    {
        auto context = Mirror.getContext(context_blob);

        auto shared_resources = SharedResources.fromObject(
            context.shared_resources);
        scope acquired_resources = shared_resources.new RequestResources;

        scope handler = new MirrorHandler(conn, context, acquired_resources);
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
        // Do nothing. The only way a Mirror request can end is if the user
        // stops it.
    }
}

/*******************************************************************************

    Client Mirror v0 request handler.

*******************************************************************************/

private scope class MirrorHandler
{
    import swarm.neo.client.RequestOnConn;
    import swarm.neo.connection.RequestOnConnBase;
    import swarm.neo.client.mixins.AllNodesRequestCore;
    import swarm.neo.client.mixins.SuspendableRequestCore;
    import swarm.neo.request.RequestEventDispatcher;
    import swarm.neo.util.MessageFiber;
    import swarm.neo.request.Command;

    import dhtproto.common.Mirror;
    import dhtproto.client.request.Mirror;
    import dhtproto.client.internal.SharedResources;

    /// Request-on-conn event dispatcher.
    private RequestOnConn.EventDispatcherAllNodes conn;

    /// Request context.
    private Mirror.Context* context;

    /// Request resource acquirer.
    private SharedResources.RequestResources resources;

    /// Reader fiber instance.
    private Reader reader;

    /// Controller fiber instance.
    private Controller controller;

    /// Batch decompression buffer.
    private void[]* decompress_buffer;

    /***************************************************************************

        Constructor.

        Params:
            conn = request-on-conn event dispatcher to communicate with node
            context = deserialised request context
            resources = request resource acquirer

    ***************************************************************************/

    public this ( RequestOnConn.EventDispatcherAllNodes conn,
        Mirror.Context* context, SharedResources.RequestResources resources )
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
        auto request = createSuspendableRequest!(Mirror)(this.conn, this.context,
            &this.connect, &this.disconnected, &this.fillPayload,
            &this.handleSupportedCode, &this.handle);
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
        return suspendableRequestConnector(this.conn,
            &this.context.shared_working.suspendable_control);
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
        Mirror.Notification notification;
        notification.node_disconnected =
            RequestNodeExceptionInfo(this.context.request_id,
            this.conn.remote_address, e);
        Mirror.notify(this.context.user_params, notification);
    }

    /***************************************************************************

        FillPayload policy, called from SuspendableRequestInitialiser template
        to add request-specific data to the initial message payload send to the
        node to begin the request.

    ***************************************************************************/

    private void fillPayload ( RequestOnConnBase.EventDispatcher.Payload payload )
    {
        this.context.shared_working.suspendable_control.fillPayload(payload);
        payload.addArray(context.user_params.args.channel);
        payload.add(context.user_params.args.settings.initial_refresh);
        payload.add(context.user_params.args.settings.periodic_refresh_s);
    }

    /***************************************************************************

        HandleStatusCode policy, called from SuspendableRequestInitialiser
        template to decide how to handle the supported code received from the
        node.

        Params:
            code = supported code received from the node in response to the
                initial message

        Returns:
            true to continue handling the request (supported); false to abort
            (unsupported)

    ***************************************************************************/

    private bool handleSupportedCode ( ubyte code )
    {
        auto supported = cast(SupportedStatus)code;
        if ( !Mirror.handleSupportedCodes(supported,
            this.context, this.conn.remote_address) )
        {
            return false; // Request/version not supported
        }

        // Handle initial started/error message from node.
        auto msg = conn.receiveValue!(MessageType)();
        with ( MessageType ) switch ( msg )
        {
            case Started:
                // Expected "request started" code. Continue handling request.
                break;

            case Error:
                // The node returned an error code. Notify the user and end the
                // request.
                Mirror.Notification n;
                n.node_error = RequestNodeInfo(
                    this.context.request_id, conn.remote_address);
                Mirror.notify(this.context.user_params, n);
                return false;

            default:
                // Treat unknown/unexpected codes as node errors.
                goto case Error;
        }

        return true;
    }

    /***************************************************************************

        Handler policy, called from AllNodesRequest template to run the
        request's main handling logic.

    ***************************************************************************/

    private void handle ( )
    {
        this.decompress_buffer = this.resources.getVoidBuffer();

        scope reader_ = new Reader;
        scope controller_ = new Controller;

        // Note: we store refs to the scope instances in class fields as a
        // convenience to be able to access them from each other (e.g. the
        // reader needs to access the controller and vice-versa). It's normally
        // not safe to store refs to scope instances outside of the scope, so we
        // need to be careful to only use them while they are in scope.
        this.reader = reader_;
        this.controller = controller_;
        scope ( exit )
        {
            this.reader = null;
            this.controller = null;
        }

        controller.fiber.start();
        reader.fiber.start();

        // Handle initial 'started' notification (and potential state change
        // requests in the notifier).
        if ( this.context.shared_working.all_nodes.num_initialising == 0 )
        {
            if ( this.context.shared_working.suspendable_control.
                allInitialised!(Mirror)(this.context) )
            {
                this.resources.request_event_dispatcher.signal(this.conn,
                    SuspendableRequestSharedWorkingData.Signal.StateChangeRequested);
            }
        }

        this.resources.request_event_dispatcher.eventLoop(this.conn);

        assert(controller.fiber.finished());
        assert(reader.fiber.finished());
    }

    /***************************************************************************

        Fiber which handles:
            1. Receiving update messages from the node and forwarding them to
               the user.
            2. Receiving and ACKing messages from the node indicating that the
               request has finished.

    ***************************************************************************/

    private class Reader
    {
        import swarm.neo.util.Batch;

        /// Fiber.
        private MessageFiber fiber;

        /***********************************************************************

            Constructor. Gets a fiber from the shared resources.

        ***********************************************************************/

        public this ( )
        {
            this.fiber = this.outer.resources.getFiber(&this.fiberMethod);
        }

        /***********************************************************************

            Fiber method.

        ***********************************************************************/

        private void fiberMethod ( )
        {
            // Receive the incoming record stream.
            bool finished;
            do
            {
                auto msg = this.outer.resources.request_event_dispatcher.receive(
                    this.fiber,
                    Message(MessageType.RecordChanged),
                    Message(MessageType.RecordRefreshBatch),
                    Message(MessageType.RecordDeleted),
                    Message(MessageType.ChannelRemoved),
                    Message(MessageType.UpdateOverflow));

                with ( MessageType ) switch ( msg.type )
                {
                    case RecordChanged:
                        auto key = *this.outer.conn.message_parser.
                            getValue!(hash_t)(msg.payload);
                        auto value = this.outer.conn.message_parser.
                            getArray!(void)(msg.payload);

                        this.recordChanged(key, value);
                        break;

                    case RecordDeleted:
                        auto key = *this.outer.conn.message_parser.
                            getValue!(hash_t)(msg.payload);

                        this.recordDeleted(key);
                        break;

                    case RecordRefreshBatch:
                        auto batch = this.outer.conn.message_parser.
                            getArray!(void)(msg.payload);

                        this.recordRefreshedBatch(batch);
                        break;

                    case ChannelRemoved:
                        finished = true;

                        Mirror.Notification n;
                        n.channel_removed = RequestNodeInfo(
                            this.outer.context.request_id,
                            this.outer.conn.remote_address);
                        Mirror.notify(this.outer.context.user_params, n);
                        break;

                    case UpdateOverflow:
                        Mirror.Notification n;
                        n.updates_lost = RequestNodeInfo(
                            this.outer.context.request_id,
                            this.outer.conn.remote_address);
                        Mirror.notify(this.outer.context.user_params, n);
                        break;

                    default:
                        assert(false);
                }
            }
            while ( !finished );

            // ACK End message
            this.outer.resources.request_event_dispatcher.send(this.fiber,
                ( RequestOnConnBase.EventDispatcher.Payload payload )
                {
                    payload.addCopy(MessageType.Ack);
                }
            );

            // It's no longer valid to handle control messages.
            this.outer.resources.request_event_dispatcher.abort(
                this.outer.controller.fiber);
        }

        /***********************************************************************

            Notifies the user that a record value has changed.

            Params:
                key = key of record which was updated
                value = new value of record

        ***********************************************************************/

        private void recordChanged ( hash_t key, Const!(void)[] value )
        {
            Mirror.Notification n;
            n.updated = RequestRecordInfo(
                this.outer.context.request_id, key, value);
            this.notify(n);
        }

        /***********************************************************************

            Notifies the user of a batch of refreshed records.

            Params:
                batch_data = batch of refreshed records

        ***********************************************************************/

        private void recordRefreshedBatch ( Const!(void)[] batch_data )
        {
            scope batch = new BatchReader!(hash_t, Const!(void)[])(
                this.outer.resources.lzo, batch_data,
                *this.outer.decompress_buffer);
            foreach ( key, value; batch )
            {
                Mirror.Notification n;
                n.refreshed = RequestRecordInfo(
                    this.outer.context.request_id, key, value);
                this.notify(n);
            }
        }

        /***********************************************************************

            Notifies the user that a record has been removed.

            Params:
                key = key of record which was removed

        ***********************************************************************/

        private void recordDeleted ( hash_t key )
        {
            Mirror.Notification n;
            n.deleted = RequestKeyInfo(this.outer.context.request_id, key);
            this.notify(n);
        }

        /***********************************************************************

            User notification helper which handles the case where the user used
            the controller in the notifier callback.

            Params:
                n = notification to send to user

        ***********************************************************************/

        private void notify ( Mirror.Notification n )
        {
            auto suspendable_control =
                &this.outer.context.shared_working.suspendable_control;

            if ( suspendable_control.notifyAndCheckStateChange!(Mirror)(
                this.outer.context, n) )
            {
                // The user used the controller in the notifier callback
                this.outer.resources.request_event_dispatcher.signal(this.outer.conn,
                    suspendable_control.Signal.StateChangeRequested);
            }
        }
    }

    /***************************************************************************

        Fiber which handles:
            1. Waiting for state change requests from the user (via the
               controller).
            2. Sending the appropriate message to the node and handling the
               returned ACK messages.

    ***************************************************************************/

    private class Controller
    {
        /// Fiber.
        private MessageFiber fiber;

        /***********************************************************************

            Constructor. Gets a fiber from the shared resources.

        ***********************************************************************/

        public this ( )
        {
            this.fiber = this.outer.resources.getFiber(&this.fiberMethod);
        }

        /***********************************************************************

            Fiber method.

        ***********************************************************************/

        private void fiberMethod ( )
        {
            SuspendableRequestControllerFiber!(Mirror, MessageType) controller;
            controller.handle(this.outer.conn, this.outer.context,
                this.outer.resources.request_event_dispatcher, this.fiber);

            // Kill the reader fiber; the request is finished.
            this.outer.resources.request_event_dispatcher.abort(
                this.outer.reader.fiber);
        }
    }
}
