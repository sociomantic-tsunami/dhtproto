/*******************************************************************************

    v0 Mirror request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.Mirror;

import ocean.util.log.Logger;

version ( UnitTest )
{
    import ocean.core.Test;
}

/// ditto
public abstract scope class MirrorProtocol_v0
{
    import swarm.neo.node.RequestOnConn;
    import swarm.neo.connection.RequestOnConnBase;
    import swarm.neo.request.RequestEventDispatcher;
    import swarm.neo.util.MessageFiber;
    import dhtproto.common.Mirror;
    import dhtproto.node.neo.request.core.Mixins;
    import ocean.transition;

    /// Mixin the constructor and resources member.
    mixin RequestCore!();

    /// Buffer used to store record values to be sent to the client.
    private void[]* value_buffer;

    /// Connection to the client.
    private RequestOnConn connection;

    /// Enum defining the possible types of updates which can be mirrored.
    protected enum UpdateType
    {
        Change,
        Deletion
    }

    /// Struct defining a single update on the mirrored channel.
    protected struct Update
    {
        /// The type of the update (see dhtproto.node.neo.request.Mirror).
        UpdateType type;

        /// Key of record which was updated.
        hash_t key;
    }

    /***************************************************************************

        Struct template implementing a simple, typed, array-based ring queue.

        Params:
            E = type of queue element

    ***************************************************************************/

    private struct Queue ( E )
    {
        import ocean.core.array.Mutation : removeShift;

        /// Backing array in which elements are stored. Must be set before using
        /// the queue.
        private E[] queue;

        /// Maximum allowed size of the queue in bytes.
        private const max_size = 256 * 1024;

        /// Maximum allowed elements of type E of the queue.
        private size_t max_elems;

        /// Current number of elements in the queue.
        private size_t num_elems;

        /// Index (E-based) of the next element to write.
        private size_t write_to_elem;

        /// Index (E-based) of the next element to read.
        private size_t read_from_elem;

        /// Tests for basic sanity of num_elems and the read/write indices.
        invariant ( )
        {
            if ( this.num_elems == 0 )
                assert(this.write_to_elem == this.read_from_elem);
            else
                assert(this.write_to_elem ==
                    (this.read_from_elem + this.num_elems) % this.max_elems);
        }

        /***********************************************************************

            Initialises the queue for use, setting up the provided array for use
            as the queue's backing storage.

            Params:
                buf = array to use to back queue storage

        ***********************************************************************/

        public void initialise ( ref void[] buf )
        {
            this.max_elems = (max_size / E.sizeof) * E.sizeof;
            buf.length = this.max_elems * E.sizeof;
            this.queue = cast(E[])buf;
        }

        /***********************************************************************

            Pushes an element to the queue, if there is space.

            Params:
                e = element to push

            Returns:
                true if the element was pushed, false if the queue is full

        ***********************************************************************/

        public bool push ( E e )
        {
            if ( this.num_elems >= this.max_elems )
                return false;

            this.queue[this.write_to_elem] = e;
            this.incWrap(this.write_to_elem);
            this.num_elems++;

            return true;
        }

        /***********************************************************************

            Pops an element from the queue. May only be called when the queue
            contains elements.

            Returns:
                popped element

        ***********************************************************************/

        public E pop ( )
        in
        {
            assert(this.num_elems > 0);
        }
        body
        {
            E e;
            e = this.queue[this.read_from_elem];
            this.incWrap(this.read_from_elem);
            this.num_elems--;

            return e;
        }

        /***********************************************************************

            Returns:
                the number of elements in the queue

        ***********************************************************************/

        public size_t length ( )
        {
            return this.num_elems;
        }

        /***********************************************************************

            Returns:
                true if the queue is full

        ***********************************************************************/

        public bool isFull ( )
        {
            return this.num_elems == this.max_elems;
        }

        /***********************************************************************

            Helper function to increment an element index, taking account of
            wrapping in the ring queue.

            Params:
                elem_index = element index to increment and wrap

        ***********************************************************************/

        private void incWrap ( ref size_t elem_index )
        {
            elem_index++;
            assert(elem_index <= this.max_elems);
            if ( elem_index == this.max_elems )
                elem_index = 0;
        }
    }

    // Tests Queue pushing, popping, and wrapping.
    unittest
    {
        void[] backing;
        Queue!(Update) q;
        q.initialise(backing);

        const elems_per_cycle = 7;
        uint write_wraps, read_wraps;
        Update update;
        for ( uint i; i < q.max_elems; i++ )
        {
            for ( uint pu; pu < elems_per_cycle; pu++ )
            {
                update.key = i * pu;
                auto pushed = q.push(update);
                test(pushed);
                if ( q.write_to_elem == 0 )
                    write_wraps++;
            }

            for ( uint po; po < elems_per_cycle; po++ )
            {
                auto popped = q.pop();
                test!("==")(popped.key, i * po);
                if ( q.read_from_elem == 0 )
                    read_wraps++;
            }
        }

        test!("==")(write_wraps, elems_per_cycle);
        test!("==")(read_wraps, elems_per_cycle);
    }

    /// Queue of updates.
    private Queue!(Update) update_queue;

    /// Queue of refreshed records.
    private Queue!(hash_t) refresh_queue;

    /// Struct wrapping fields and logic for counting queue overflows and
    /// deciding when to notify the client that overflows have occurred.
    private struct UpdateQueueOverflows
    {
        import core.stdc.time : time_t, time;

        /// The number of records which could not be pushed to the update queue
        /// because it was full. Cleared each time a notification is sent to the
        /// client.
        private uint count_since_last_notification;

        /// Timestamp at which the last queue overflow occurred. Storing this
        /// value as seconds allows us to limit the rate of client
        /// notifications to once per second.
        private time_t last_overflow_time;

        /// Timestamp at which the client was last notified of an overflow.
        private time_t last_notified_overflow_time;

        /***********************************************************************

            Called to indicate that an update could not be pushed into the queue
            because it was full.

        ***********************************************************************/

        public void opPostInc ( )
        {
            this.last_overflow_time = time(null);
            this.count_since_last_notification++;
        }

        /***********************************************************************

            Returns:
                true if it's time to send a notification to the client

        ***********************************************************************/

        public bool notification_pending ( )
        {
            return this.last_overflow_time > this.last_notified_overflow_time;
        }

        /***********************************************************************

            Called to indicate that a notification was sent to the client.

        ***********************************************************************/

        public void notification_sent ( )
        {
            this.last_notified_overflow_time = this.last_overflow_time;
            this.count_since_last_notification = 0;
        }
    }

    /// Overflow notification tracker.
    private UpdateQueueOverflows update_queue_overflows;

    /// Codes used when resuming the fiber to interrupt waiting for I/O.
    private enum NodeFiberResumeCode : ubyte
    {
        PushedToQueue = 1,
        ChannelRemoved = 2,
        PeriodicRefresh = 3,
        RefreshQueueEmptied = 4,
        QueueOverflowNotification = 5,
        ResumeAfterSuspension = 6
    }

    /// If true, the request, upon starting, will immediately send all records
    /// in the channel to the client.
    private bool initial_refresh;

    /// If non-zero, the request will repeatedly send all records in the channel
    /// to the client after every specified period. If zero, no periodic
    /// refreshes will occur.
    private uint periodic_refresh_s;

    /// Writer fiber instance.
    private Writer writer;

    /// Controller fiber instance.
    private Controller controller;

    /// PeriodicRefresh fiber instance.
    private PeriodicRefresh periodic_refresh;

    /// Set by the Writer when the iteration over the records has finished. Used
    /// by the Controller to ignore incoming messages from that point. This is
    /// to avoid a race condition between the Finished message and a control
    /// message sent by the client.
    private bool has_ended;

    /***************************************************************************

        Request handler. Reads the initial message from the client, responds to
        the client with a status code, and starts the request handling fibers.

        Params:
            connection = connection to client
            msg_payload = initial message read from client to begin the request
                (the request code and version are assumed to be extracted)

    ***************************************************************************/

    final public void handle ( RequestOnConn connection,
        Const!(void)[] msg_payload )
    {
        this.connection = connection;

        // Parse initial message from client.
        bool start_suspended;
        cstring channel;
        this.connection.event_dispatcher.message_parser.parseBody(msg_payload,
            start_suspended, channel, this.initial_refresh,
            this.periodic_refresh_s);

        auto ok = this.prepareChannel(channel);

        // Send status code
        this.connection.event_dispatcher.send(
            ( RequestOnConnBase.EventDispatcher.Payload payload )
            {
                payload.addConstant(ok
                    ? RequestStatusCode.Started : RequestStatusCode.Error);
            }
        );

        if ( !ok )
            return;

        this.value_buffer = this.resources.getVoidBuffer();
        this.update_queue.initialise(*this.resources.getVoidBuffer());
        this.refresh_queue.initialise(*this.resources.getVoidBuffer());

        // Start the three fibers which form the request handling logic.
        scope writer_ = new Writer;
        scope controller_ = new Controller;
        scope periodic_refresh_ = new PeriodicRefresh;

        // Note: we store refs to the scope instances in class fields as a
        // convenience to be able to access them from each other (e.g. the
        // writer needs to access the controller and vice-versa). It's normally
        // not safe to store refs to scope instances outside of the scope, so we
        // need to be careful to only use them while they are in scope.
        this.writer = writer_;
        this.controller = controller_;
        this.periodic_refresh = periodic_refresh_;
        scope ( exit )
        {
            this.writer = null;
            this.controller = null;
            this.periodic_refresh = null;
        }

        if ( start_suspended )
            this.writer.suspender.requestSuspension();

        // Now the Writer fiber is instantiated, it's safe to register with the
        // channel for updates. (When an update occurs, this.updated() will be
        // called, which requires this.writer to be non-null.)
        this.registerForUpdates();
        scope ( exit ) this.unregisterForUpdates();

        this.periodic_refresh.fiber.start();
        this.controller.fiber.start();
        this.writer.fiber.start();
        this.resources.request_event_dispatcher.eventLoop(
            this.connection.event_dispatcher);
    }

    /***************************************************************************

        Called by the implementing class when notified by the storage engine of
        an update. Adds the update to the update queue and wakes up the Writer
        fiber, if it's waiting for something to send. If the update queue is
        full, increments the counter of missed updates and (at most once per
        second) wakes up the Writer fiber to notify the user of the overflow.

        Params:
            update = update to push to the queue

    ***************************************************************************/

    final protected void updated ( Update update )
    {
        auto resume_code = NodeFiberResumeCode.PushedToQueue;

        auto pushed = this.update_queue.push(update);
        if ( !pushed )
        {
            this.update_queue_overflows++;
            if ( !this.update_queue_overflows.notification_pending() )
                return;

            auto client_addr = this.connection.event_dispatcher.remote_address();
            log.warn("Mirror request on channel '{}', client {}:{} -- " ~
                "update queue overflowed, {} updates discarded",
                this.channelName(), client_addr.address_bytes, client_addr.port,
                this.update_queue_overflows.count_since_last_notification);

            resume_code = NodeFiberResumeCode.QueueOverflowNotification;
        }

        if ( this.writer.suspended_waiting_for_events )
            this.resources.request_event_dispatcher.signal(
                this.connection.event_dispatcher, resume_code);
    }

    /***************************************************************************

        Called by the PeriodicRefresh fiber when a record is iterated. Adds the
        record key to the refresh queue and wakes up the Writer fiber, if it's
        waiting for something to send.

        Params:
            key = key of record to push to the refresh queue

    ***************************************************************************/

    private void refreshed ( hash_t key )
    in
    {
        assert(!this.refresh_queue.isFull());
    }
    body
    {
        auto pushed = this.refresh_queue.push(key);
        // The logic in PeriodicRefresh ensures that the refresh queue will
        // never overflow.
        assert(pushed);

        if ( this.writer.suspended_waiting_for_events )
            this.resources.request_event_dispatcher.signal(
                this.connection.event_dispatcher,
                NodeFiberResumeCode.PushedToQueue);
    }

    /***************************************************************************

        Called by the implementing class when notified by the storage engine
        that the mirrored channel has been removed.

    ***************************************************************************/

    final protected void channelRemoved ( )
    {
        if ( this.writer.suspended_waiting_for_events )
            this.resources.request_event_dispatcher.signal(
                this.connection.event_dispatcher,
                NodeFiberResumeCode.ChannelRemoved);
    }

    /***************************************************************************

        Performs any logic needed to start mirroring the channel of the given
        name.

        Params:
            channel_name = channel to mirror

        Returns:
            true if the channel may be used, false to abort the request

    ***************************************************************************/

    abstract protected bool prepareChannel ( cstring channel_name );

    /***************************************************************************

        Returns:
            the name of the channel being mirrored (for logging)

    ***************************************************************************/

    abstract protected cstring channelName ( );

    /***************************************************************************

        Registers this request to receive updates on the channel.

    ***************************************************************************/

    abstract protected void registerForUpdates ( );

    /***************************************************************************

        Unregisters this request from receiving updates on the channel.

    ***************************************************************************/

    abstract protected void unregisterForUpdates ( );

    /***************************************************************************

        Gets the value of the record with the specified key, if it exists.

        Params:
            key = key of record to get from storage
            buf = buffer to write the value into

        Returns:
            record value or null, if the record does not exist

    ***************************************************************************/

    abstract protected void[] getRecordValue ( hash_t key, ref void[] buf );

    /***************************************************************************

        Called to begin a complete iteration over the channel being mirrored.

    ***************************************************************************/

    abstract protected void startIteration ( );

    /***************************************************************************

        Gets the key of the next record in the iteration.

        Params:
            hash_key = output value to receive the next key

        Returns:
            true if hash_key was set or false if the iteration is finished

    ***************************************************************************/

    abstract protected bool iterateNext ( out hash_t hash_key );

    /***************************************************************************

        Fiber which handles:
            1. Popping updates from the queue and forwarding them to the client.
            2. If the channel is removed, informing the client of this.

    ***************************************************************************/

    private class Writer
    {
        import swarm.neo.util.DelayedSuspender;

        /// Fiber.
        public MessageFiber fiber;

        /// Helper to allow other fibers to request writes to the client to be
        /// suspended.
        public DelayedSuspender suspender;

        /// Flag set to true when suspended waiting for updates.
        private bool suspended_waiting_for_events;

        /// Flag set when the channel being mirrored has been removed.
        private bool channel_removed;

        /// Loop counter used for yielding after every 10 records is sent.
        private uint yield_counter;

        /***********************************************************************

            Constructor. Gets a fiber from the shared resources.

        ***********************************************************************/

        public this ( )
        {
            this.fiber = this.outer.resources.getFiber(&this.fiberMethod);
            this.suspender = DelayedSuspender(
                this.outer.resources.request_event_dispatcher,
                this.outer.connection.event_dispatcher,
                this.fiber, NodeFiberResumeCode.ResumeAfterSuspension);
        }

        /***********************************************************************

            Fiber method.

        ***********************************************************************/

        private void fiberMethod ( )
        {
            do
            {
                // Pop and send all updates currently in the queues.
                this.sendFromQueues();

                // Send a message notifying the user that the updates queue
                // overflowed, if one is pending.
                this.sendPendingOverflowNotification();

                // Wait for record updates or channel removed.
                if ( !this.channel_removed )
                    this.waitForEvents();
            }
            while ( !this.channel_removed );

            // The request is now finished. Inform client of this and ignore any
            // further incoming control messages.
            this.outer.has_ended = true;
            this.outer.resources.request_event_dispatcher.send(this.fiber,
                ( RequestOnConnBase.EventDispatcher.Payload payload )
                {
                    payload.addConstant(MessageType.ChannelRemoved);
                }
            );

            // Wait for ACK from client
            this.outer.resources.request_event_dispatcher.receive(this.fiber,
                Message(MessageType.Ack));

            // It's no longer valid to handle control messages.
            this.outer.resources.request_event_dispatcher.abort(
                this.outer.controller.fiber);

            // Cancel the periodic refresher.
            this.outer.resources.request_event_dispatcher.abort(
                this.outer.periodic_refresh.fiber);
        }

        /***********************************************************************

            Sends all queued updates / refreshes.

        ***********************************************************************/

        private void sendFromQueues ( )
        {
            while ( !this.channel_removed &&
                (this.outer.update_queue.length || this.outer.refresh_queue.length) )
            {
                // If suspended, wait until resumed.
                this.suspender.suspendIfRequested();

                // Pop and send an update, if available.
                if ( this.outer.update_queue.length )
                    this.sendQueuedUpdate();

                // Pop and send a refresh, if available.
                if ( this.outer.refresh_queue.length )
                    this.sendQueuedRefresh();

                this.outer.resources.request_event_dispatcher.periodicYield(
                    this.fiber, this.yield_counter, 10);
            }
        }

        /***********************************************************************

            Sends the next element in the update queue.

        ***********************************************************************/

        private void sendQueuedUpdate ( )
        in
        {
            assert(this.outer.update_queue.length > 0);
        }
        body
        {
            auto update = this.outer.update_queue.pop();
            with ( UpdateType ) switch ( update.type )
            {
                case Change:
                    if ( this.outer.getRecordValue(update.key,
                        *this.outer.value_buffer) !is null )
                    {
                        this.sendRecordChanged(update.key,
                            *this.outer.value_buffer);
                    }
                    // else: the record no longer exists; just ignore
                    break;

                case Deletion:
                    this.sendRecordDeleted(update.key);
                    break;

                default:
                    assert(false);
            }
        }

        /***********************************************************************

            Sends the next element in the refresh queue.

        ***********************************************************************/

        private void sendQueuedRefresh ( )
        in
        {
            assert(this.outer.refresh_queue.length > 0);
        }
        body
        {
            auto key = this.outer.refresh_queue.pop();
            if ( this.outer.getRecordValue(key,
                *this.outer.value_buffer) !is null )
            {
                this.sendRecordRefreshed(key, *this.outer.value_buffer);
            }
            // else: the record no longer exists; just ignore

            // Let the refresh fiber know when the refresh queue is emptied.
            if ( this.outer.refresh_queue.length == 0 )
                this.outer.periodic_refresh.queueFlushed();
        }

        /***********************************************************************

            Sends a message to the client, informing it that a record value has
            changed.

            Params:
                key = key of record which was updated
                value = new value of record

        ***********************************************************************/

        private void sendRecordChanged ( hash_t key, Const!(void)[] value )
        {
            this.outer.resources.request_event_dispatcher.send(this.fiber,
                ( RequestOnConnBase.EventDispatcher.Payload payload )
                {
                    payload.addConstant(MessageType.RecordChanged);
                    payload.add(key);
                    payload.addArray(value);
                }
            );
        }

        /***********************************************************************

            Sends a message to the client, informing it that a record value has
            been refreshed.

            Params:
                key = key of record which was refreshed
                value = value of record

        ***********************************************************************/

        private void sendRecordRefreshed ( hash_t key, Const!(void)[] value )
        {
            this.outer.resources.request_event_dispatcher.send(this.fiber,
                ( RequestOnConnBase.EventDispatcher.Payload payload )
                {
                    payload.addConstant(MessageType.RecordRefresh);
                    payload.add(key);
                    payload.addArray(value);
                }
            );
        }

        /***********************************************************************

            Sends a message to the client, informing it that a record has been
            removed.

            Params:
                key = key of record which was removed

        ***********************************************************************/

        private void sendRecordDeleted ( hash_t key )
        {
            this.outer.resources.request_event_dispatcher.send(this.fiber,
                ( RequestOnConnBase.EventDispatcher.Payload payload )
                {
                    payload.addConstant(MessageType.RecordDeleted);
                    payload.add(key);
                }
            );
        }

        /***********************************************************************

            If update queue overflows have occurred and the update queue
            overflow tracker says it's time to send a notification to the
            client, do so.

        ***********************************************************************/

        private void sendPendingOverflowNotification ( )
        {
            if ( !this.outer.update_queue_overflows.notification_pending() )
                return;

            this.outer.resources.request_event_dispatcher.send(this.fiber,
                ( RequestOnConnBase.EventDispatcher.Payload payload )
                {
                    payload.addConstant(MessageType.UpdateOverflow);
                }
            );

            this.outer.update_queue_overflows.notification_sent();
        }

        /***********************************************************************

            Suspends the fiber until a new update is pushed to the queue.

        ***********************************************************************/

        private void waitForEvents ( )
        {
            this.suspended_waiting_for_events = true;
            scope ( exit )
                this.suspended_waiting_for_events = false;

            auto event = this.outer.resources.request_event_dispatcher.nextEvent(this.fiber,
                Signal(NodeFiberResumeCode.PushedToQueue),
                Signal(NodeFiberResumeCode.QueueOverflowNotification),
                Signal(NodeFiberResumeCode.ChannelRemoved));
            assert(event.active == event.active.signal,
                "Unexpected event: waiting only for fiber resume code");

            with ( NodeFiberResumeCode ) switch ( event.signal.code )
            {
                case PushedToQueue:
                case QueueOverflowNotification:
                    break;
                case ChannelRemoved:
                    this.channel_removed = true;
                    break;
                default:
                    assert(false);
            }
        }
    }

    /***************************************************************************

        Fiber which handles:
            1. Reading control messages from the client.
            2. Sending an ACK message back (the client relies on ACKs to
               re-enable the user-facing controller).
            3. Controlling the other fibers, as appropriate, to carry out the
               control messages from the client.

    ***************************************************************************/

    private class Controller
    {
        /// Fiber.
        public MessageFiber fiber;

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
            bool stopped;
            do
            {
                // Receive message from client.
                auto message =
                    this.outer.resources.request_event_dispatcher.receive(
                        this.fiber,
                        Message(MessageType.Suspend), Message(MessageType.Resume),
                        Message(MessageType.Stop));

                if ( this.outer.has_ended )
                    continue;

                // Send ACK. The protocol guarantees that the client will not
                // send any further messages until it has received the ACK.
                this.outer.resources.request_event_dispatcher.send(this.fiber,
                    ( RequestOnConnBase.EventDispatcher.Payload payload )
                    {
                        payload.addConstant(MessageType.Ack);
                    }
                );

                with ( MessageType ) switch ( message.type )
                {
                    case Suspend:
                        this.outer.writer.suspender.requestSuspension();
                        this.outer.periodic_refresh.suspender.requestSuspension();
                        break;
                    case Resume:
                        this.outer.writer.suspender.resumeIfSuspended();
                        this.outer.periodic_refresh.suspender.resumeIfSuspended();
                        break;
                    case Stop:
                        stopped = true;

                        // End both other fibers. The request is finished.
                        this.outer.resources.request_event_dispatcher.abort(
                            this.outer.writer.fiber);
                        this.outer.resources.request_event_dispatcher.abort(
                            this.outer.periodic_refresh.fiber);
                        break;
                    default:
                        assert(false);
                }
            }
            while ( !stopped );
        }
    }

    /***************************************************************************

        Fiber which handles (if requested by the client):
            1. The initial refresh of all records in the channel.
            2. The periodic refresh of all records in the channel.

    ***************************************************************************/

    private class PeriodicRefresh
    {
        import swarm.neo.util.DelayedSuspender;

        /// Fiber.
        public MessageFiber fiber;

        /// Helper to allow other fibers to request writes to the client to be
        /// suspended.
        public DelayedSuspender suspender;

        /// Enum defining the states of the fiber.
        private enum WaitingFor
        {
            /// Fiber running.
            Nothing,

            /// Fiber suspended waiting for the periodic timer to fire.
            Timer,

            /// Fiber suspended waiting for everything in the refresh queue to
            /// be sent to the client.
            QueueEmptied
        }

        /// Fiber state.
        private WaitingFor waiting_for;

        /***********************************************************************

            Constructor. Gets a fiber from the shared resources.

        ***********************************************************************/

        public this ( )
        {
            this.fiber = this.outer.resources.getFiber(&this.fiberMethod);
            this.suspender = DelayedSuspender(
                this.outer.resources.request_event_dispatcher,
                this.outer.connection.event_dispatcher,
                this.fiber, NodeFiberResumeCode.ResumeAfterSuspension);
        }

        /***********************************************************************

            Fiber method.

        ***********************************************************************/

        private void fiberMethod ( )
        {
            // Do an initial refresh immediately, if requested.
            if ( this.outer.initial_refresh )
                this.refresh();

            // If no periodic refresh, exit the fiber.
            if ( this.outer.periodic_refresh_s == 0 )
                return;

            // Set up periodic timer.
            auto timer = this.outer.resources.getTimer(
                this.outer.periodic_refresh_s, 0,
                {
                    if ( this.waiting_for == WaitingFor.Timer )
                    {
                        this.outer.resources.request_event_dispatcher.signal(
                            this.outer.connection.event_dispatcher,
                            NodeFiberResumeCode.PeriodicRefresh);
                    }
                    // else: if the fiber is already running, a refresh
                    // cycle is in progress. Just let it finish.
                }
            );

            timer.start();
            scope ( exit )
                timer.stop();

            do
            {
                // Wait for the timer to fire.
                this.waiting_for = WaitingFor.Timer;
                this.outer.resources.request_event_dispatcher.nextEvent(
                    this.fiber,
                    Signal(NodeFiberResumeCode.PeriodicRefresh));
                this.waiting_for = WaitingFor.Nothing;

                this.refresh();
            }
            while ( true );
        }

        /***********************************************************************

            Performs a single refresh cycle, iterating over all records in the
            mirrored channel and pushing them to the update queue.

        ***********************************************************************/

        private void refresh ( )
        {
            // Iterate over the storage engine.
            this.outer.startIteration();

            hash_t key;
            while ( this.outer.iterateNext(key) )
            {
                this.suspender.suspendIfRequested();

                // If the refresh queue is full, wait until it's been emptied.
                if ( this.outer.refresh_queue.isFull() )
                {
                    this.waiting_for = WaitingFor.QueueEmptied;
                    this.outer.resources.request_event_dispatcher.nextEvent(
                        this.fiber,
                        Signal(NodeFiberResumeCode.RefreshQueueEmptied));
                    this.waiting_for = WaitingFor.Nothing;
                }

                // Add the iterated key to the refresh queue and wake up the
                // Writer fiber, if it's waiting for data to send.
                this.outer.refreshed(key);
            }
        }

        /***********************************************************************

            Called by the Writer fiber when the queue of refreshed records has
            been emptied (i.e. sent to the client). Wakes up this fiber, if it's
            waiting for this event.

        ***********************************************************************/

        private void queueFlushed ( )
        {
            if ( this.waiting_for == WaitingFor.QueueEmptied )
            {
                this.outer.resources.request_event_dispatcher.signal(
                    this.outer.connection.event_dispatcher,
                    NodeFiberResumeCode.RefreshQueueEmptied);
            }
        }
    }
}

/// Static module logger
static private Logger log;

static this ( )
{
    log = Log.lookup("dhtproto.node.neo.request.Mirror");
}
