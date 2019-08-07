/*******************************************************************************

    Client DHT GetAll v0 request handler.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.internal.GetAll;

import ocean.transition;
import ocean.util.log.Logger;
import ocean.core.Verify;

/*******************************************************************************

    GetAll request implementation.

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

public struct GetAll
{
    import dhtproto.common.GetAll;
    public import dhtproto.client.request.GetAll;
    import dhtproto.common.RequestCodes;
    import dhtproto.client.NotifierTypes;
    import swarm.util.RecordBatcher;
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

    mixin SuspendableController!(GetAll, IController, MessageType);

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

    mixin RequestCore!(RequestType.AllNodes, RequestCode.GetAll, 0, Args,
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
        auto context = GetAll.getContext(context_blob);

        auto shared_resources = SharedResources.fromObject(
            context.shared_resources);
        scope acquired_resources = shared_resources.new RequestResources;

        scope handler = new GetAllHandler(conn, context, acquired_resources);
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
        auto context = GetAll.getContext(context_blob);

        if ( !context.shared_working.suspendable_control.stopped_notification_done )
        {
            Notification n;
            n.finished = RequestInfo(context.request_id);
            GetAll.notify(context.user_params, n);
        }
    }
}

/*******************************************************************************

    Client GetAll v0 request handler.

*******************************************************************************/

private scope class GetAllHandler
{
    import swarm.neo.client.RequestOnConn;
    import swarm.neo.connection.RequestOnConnBase;
    import swarm.neo.client.mixins.AllNodesRequestCore;
    import swarm.neo.client.mixins.SuspendableRequestCore;
    import swarm.neo.request.Command;
    import swarm.neo.request.RequestEventDispatcher;
    import swarm.neo.util.MessageFiber;
    import swarm.util.RecordBatcher;

    import dhtproto.common.GetAll;
    import dhtproto.client.request.GetAll;
    import dhtproto.client.internal.SharedResources;

    /// Request-on-conn event dispatcher.
    private RequestOnConn.EventDispatcherAllNodes conn;

    /// Request context.
    private GetAll.Context* context;

    /// Request resource acquirer.
    private SharedResources.RequestResources resources;

    /// Request event dispatcher.
    private RequestEventDispatcher request_event_dispatcher;

    /// Reader fiber instance.
    private Reader reader;

    /// Controller fiber instance.
    private Controller controller;

    /// Record batch received from the node.
    private RecordBatch batch;

    /// Flag indicating that the request has successfully received some data.
    private bool received_a_batch;

    /// Flag indicating that the request should continue where it left off,
    /// after a disconnection.
    private bool continuing;

    /// Key of last record received.
    private hash_t last_key;

    /***************************************************************************

        Constructor.

        Params:
            conn = request-on-conn event dispatcher to communicate with node
            context = deserialised request context
            resources = request resource acquirer

    ***************************************************************************/

    public this ( RequestOnConn.EventDispatcherAllNodes conn,
        GetAll.Context* context, SharedResources.RequestResources resources )
    {
        this.conn = conn;
        this.context = context;
        this.resources = resources;

        this.batch = resources.getRecordBatch();
    }

    /***************************************************************************

        Main request handling entry point.

    ***************************************************************************/

    public void run ( )
    {
        auto request = createSuspendableRequest!(GetAll)(this.conn, this.context,
            &this.connect, &this.disconnected, &this.fillPayload,
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
        auto r = suspendableRequestConnector(this.conn,
            &this.context.shared_working.suspendable_control);
        return r;
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
        GetAll.Notification notification;
        notification.node_disconnected =
            RequestNodeExceptionInfo(this.context.request_id,
            this.conn.remote_address, e);
        GetAll.notify(this.context.user_params, notification);

        // If at least one record was received before the connection error,
        // set the `continuing` flag to inform the node (after the connection is
        // re-established) to carry on from the last key received.
        if ( this.received_a_batch )
            this.continuing = true;
    }

    /***************************************************************************

        FillPayload policy, called from SuspendableRequestInitialiser template
        to add request-specific data to the initial message payload send to the
        node to begin the request.

        Params:
            payload = message payload to be filled

    ***************************************************************************/

    private void fillPayload ( RequestOnConnBase.EventDispatcher.Payload payload )
    {
        this.context.shared_working.suspendable_control.fillPayload(payload);
        payload.addArray(this.context.user_params.args.channel);
        payload.add(this.continuing);
        payload.add(this.last_key); // If not continuing, this field is ignored
        payload.add(this.context.user_params.args.settings.keys_only);
        payload.addArray(this.context.user_params.args.settings.value_filter);
    }

    /***************************************************************************

        Handler policy, called from AllNodesRequest template to run the
        request's main handling logic.

    ***************************************************************************/

    private void handle ( )
    {
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
                GetAll.Notification n;
                n.node_error = RequestNodeInfo(
                    this.context.request_id, conn.remote_address);
                GetAll.notify(this.context.user_params, n);
                return;

            default:
                // Treat unknown/unexpected codes as node errors.
                goto case Error;
        }

        scope reader_ = new Reader;
        scope controller_ = new Controller;

        this.request_event_dispatcher.initialise(&this.resources.getVoidBuffer);

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
                allInitialised!(GetAll)(this.context) )
            {
                this.request_event_dispatcher.signal(this.conn,
                    SuspendableRequestSharedWorkingData.Signal.StateChangeRequested);
            }
        }

        this.request_event_dispatcher.eventLoop(this.conn);

        verify(controller.fiber.finished());
        verify(reader.fiber.finished());
    }

    /***************************************************************************

        Fiber which handles:
            1. Receiving batches of records from the node and forwarding them to
               the user.
            2. Receiving and ACKing messages from the node indicating that the
               request has finished.

    ***************************************************************************/

    private class Reader
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
            // Receive the incoming record stream.
            bool finished;
            do
            {
                auto msg = this.outer.request_event_dispatcher.receive(
                    this.fiber,
                    Message(MessageType.RecordBatch),
                    Message(MessageType.Finished));

                with ( MessageType ) switch ( msg.type )
                {
                    case RecordBatch:
                        auto batch = this.outer.conn.message_parser.
                            getArray!(void)(msg.payload);

                        this.receivedBatch(batch);
                        break;

                    case Finished:
                        finished = true;
                        break;

                    default:
                        assert(false);
                }
            }
            while ( !finished );

            // ACK Finished message
            this.outer.request_event_dispatcher.send(this.fiber,
                ( RequestOnConnBase.EventDispatcher.Payload payload )
                {
                    payload.addCopy(MessageType.Ack);
                }
            );

            // It's no longer valid to handle control messages.
            this.outer.request_event_dispatcher.abort(
                this.outer.controller.fiber);
        }

        /***********************************************************************

            Handles a received batch, decompressing the batch and sending the
            contained records to the user.

            Params:
                compressed_batch = compressed record batch received from the
                    node

        ***********************************************************************/

        private void receivedBatch ( Const!(void)[] compressed_batch )
        {
            this.outer.received_a_batch = true;

            auto suspendable_control =
                &this.outer.context.shared_working.suspendable_control;

            this.outer.batch.decompress(cast(Const!(ubyte)[])compressed_batch);

            void notify ( GetAll.Notification notification )
            {
                if ( suspendable_control.notifyAndCheckStateChange!(GetAll)(
                    this.outer.context, notification) )
                {
                    // The user used the controller in the notifier callback
                    this.outer.request_event_dispatcher.signal(
                        this.outer.conn,
                        suspendable_control.Signal.StateChangeRequested);
                }
            }

            if ( this.outer.context.user_params.args.settings.keys_only )
            {
                foreach ( key; this.outer.batch )
                {
                    hash_t hash_key = *(cast(hash_t*)key.ptr);

                    GetAll.Notification n;
                    n.received_key = RequestKeyInfo(
                        this.outer.context.request_id, hash_key);
                    notify(n);

                    this.outer.last_key = hash_key;
                }
            }
            else
            {
                foreach ( key, value; this.outer.batch )
                {
                    hash_t hash_key = *(cast(hash_t*)key.ptr);

                    GetAll.Notification n;
                    n.received = RequestRecordInfo(
                        this.outer.context.request_id, hash_key, value);
                    notify(n);

                    this.outer.last_key = hash_key;
                }
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
            SuspendableRequestControllerFiber!(GetAll, MessageType) controller;
            controller.handle(this.outer.conn, this.outer.context,
                &this.outer.request_event_dispatcher, this.fiber);

            // Kill the reader fiber; the request is finished.
            this.outer.request_event_dispatcher.abort(
                this.outer.reader.fiber);
        }
    }
}
