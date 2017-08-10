/*******************************************************************************

    v0 GetAll request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.GetAll;

import ocean.util.log.Log;

/// ditto
public abstract scope class GetAllProtocol_v0
{
    import swarm.neo.node.RequestOnConn;
    import swarm.neo.connection.RequestOnConnBase;
    import swarm.neo.request.RequestEventDispatcher;
    import swarm.neo.util.MessageFiber;
    import swarm.util.RecordBatcher;
    import dhtproto.common.GetAll;
    import dhtproto.node.neo.request.core.Mixins;
    import ocean.transition;

    /// Mixin the constructor and resources member.
    mixin RequestCore!();

    /// Buffer used to store record values to be sent to the client.
    private void[]* value_buffer;

    /// Batch of records to send.
    private RecordBatcher batcher;

    /// Destination buffer for compressing batches of records.
    private void[]* compressed_batch;

    /// Connection to the client.
    private RequestOnConn connection;

    /// Writer fiber instance.
    private Writer writer;

    /// Controller fiber instance.
    private Controller controller;

    /// Set by the Writer when the iteration over the records has finished. Used
    /// by the Controller to ignore incoming messages from that point. This is
    /// to avoid a race condition between the Finished message and a control
    /// message sent by the client.
    private bool has_ended;

    /// If true, only record keys will be sent, no values.
    private bool keys_only;

    /// Value filtering wrapper struct.
    private struct ValueFilter
    {
        import ocean.text.Search;

        /// Sub-array matcher. (Type ubyte as doesn't compile with void.)
        private SearchFruct!(Const!(ubyte)) matcher;

        /// Filtering active?
        private bool active;

        /***********************************************************************

            Initialises the filter from the specified filter array.

            Params:
                filter = sub-array to filter records by. If empty, no filtering
                    is employed

        ***********************************************************************/

        public void init ( in void[] filter )
        {
            if ( filter.length > 0 )
            {
                this.matcher = search(cast(Const!(ubyte)[])filter);
                this.active = true;
            }
        }

        /***********************************************************************

            Checks whether the provided record value passes the filter or not.

            Params:
                value = value to filter

            Returns:
                true if the value passes (i.e. matches) the filter or if
                filtering is not active

        ***********************************************************************/

        public bool match ( in void[] value )
        {
            if ( this.active )
                return this.matcher.forward(cast(Const!(ubyte)[])value)
                    < value.length;
            else
                return true;
        }
    }

    /// Value filter.
    private ValueFilter filter;

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
        bool continuing;
        hash_t continue_from;
        Const!(void)[] value_filter;
        this.connection.event_dispatcher.message_parser.parseBody(msg_payload,
            start_suspended, channel, continuing, continue_from, this.keys_only,
            value_filter);

        bool ok;
        if ( continuing )
            ok = this.continueIteration(channel, continue_from);
        else
            ok = this.startIteration(channel);

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

        // Set up filtering.
        this.filter.init(value_filter);

        // Acquire required resources.
        this.value_buffer = this.resources.getVoidBuffer();
        this.compressed_batch = this.resources.getVoidBuffer();
        this.batcher = this.resources.getRecordBatcher();

        // Start the two fibers which form the request handling logic.
        scope writer_ = new Writer;
        scope controller_ = new Controller;

        // Note: we store refs to the scope instances in class fields as a
        // convenience to be able to access them from each other (e.g. the
        // writer needs to access the controller and vice-versa). It's normally
        // not safe to store refs to scope instances outside of the scope, so we
        // need to be careful to only use them while they are in scope.
        this.writer = writer_;
        this.controller = controller_;
        scope ( exit )
        {
            this.writer = null;
            this.controller = null;
        }

        if ( start_suspended )
            this.writer.suspender.requestSuspension();

        this.controller.fiber.start();
        this.writer.fiber.start();
        this.resources.request_event_dispatcher.eventLoop(
            this.connection.event_dispatcher);
    }

    /***************************************************************************

        Called to begin the iteration over the channel being fetched.

        Params:
            channel = name of channel to iterate over

        Returns:
            true if the iteration has been initialised, false to abort the
            request

    ***************************************************************************/

    abstract protected bool startIteration ( cstring channel );

    /***************************************************************************

        Called to continue the iteration over the channel being fetched,
        continuing from the specified hash (the last record received by the
        client).

        Params:
            channel = name of channel to iterate over
            continue_from = hash of last record received by the client. The
                iteration will continue from the next hash in the channel

        Returns:
            true if the iteration has been initialised, false to abort the
            request

    ***************************************************************************/

    abstract protected bool continueIteration ( cstring channel,
        hash_t continue_from );

    /***************************************************************************

        Gets the next record in the iteration, if one exists.

        Params:
            key = receives the key of the next record, if available
            value = receives the value of the next record, if available

        Returns:
            true if a record was returned via the out arguments or false if the
            iteration is finished

    ***************************************************************************/

    abstract protected bool getNext ( out hash_t key, ref void[] value );

    /***************************************************************************

        Fiber which handles:
            1. Iterating over the channel.
            2. Forming batches of records and forwarding them to the client.
            3. Informing the client when the iteration ends.

    ***************************************************************************/

    private class Writer
    {
        import swarm.neo.util.DelayedSuspender;

        /// Fiber.
        public MessageFiber fiber;

        /// Helper to allow other fibers to request writes to the client to be
        /// suspended.
        public DelayedSuspender suspender;

        /***********************************************************************

            Constructor. Gets a fiber from the shared resources.

        ***********************************************************************/

        public this ( )
        {
            this.fiber = this.outer.resources.getFiber(&this.fiberMethod);
            this.suspender = DelayedSuspender(this.fiber);
        }

        /***********************************************************************

            Fiber method.

        ***********************************************************************/

        private void fiberMethod ( )
        {
            hash_t key;
            uint yield_counter;

            // Iterate over the channel and send each record to the client.
            while ( this.outer.getNext(key, *this.outer.value_buffer) )
            {
                if ( !this.outer.filter.match(*this.outer.value_buffer) )
                    continue;

                cstring key_slice = (cast(char*)&key)[0..key.sizeof];
                auto add_result = this.addToBatch(key_slice,
                    cast(cstring)*this.outer.value_buffer);

                // If suspended, wait until resumed.
                this.suspender.suspendIfRequested();

                with ( RecordBatcher.AddResult ) switch ( add_result )
                {
                    case Added:
                        // Can add more data to the batch
                        break;
                    case BatchFull:
                        // New record does not fit into this batch, send it
                        // and add the record to the next batch
                        this.sendBatch();
                        add_result = this.addToBatch(key_slice,
                            cast(cstring)*this.outer.value_buffer);
                        assert(add_result == Added);
                        break;
                    case TooBig:
                        // Impossible to fit the record even in empty batch
                        log.warn(
                            "GetAll: Large record 0x{:x16} ({} bytes) skipped.",
                            key, this.outer.value_buffer.length);
                        break;
                    default:
                        assert(false, "Invalid AddResult in switch");
                }

                this.outer.resources.request_event_dispatcher.periodicYield(
                    this.fiber, yield_counter, 10);
            }

            // Handle the last pending batch at the end of the iteration (does
            // nothing if no records are pending)
            this.sendBatch();

            // The request is now finished. Inform client of this and ignore any
            // further incoming control messages.
            this.outer.has_ended = true;
            this.outer.resources.request_event_dispatcher.send(this.fiber,
                ( RequestOnConnBase.EventDispatcher.Payload payload )
                {
                    payload.addConstant(MessageType.Finished);
                }
            );

            // Wait for ACK from client
            this.outer.resources.request_event_dispatcher.receive(this.fiber,
                Message(MessageType.Ack));

            // It's no longer valid to handle control messages.
            this.outer.resources.request_event_dispatcher.abort(
                this.outer.controller.fiber);
        }

        /***********************************************************************

            Tries to add the provided record to the batch. If a keys-only
            iteration was requested by the client, only the key is added to the
            batch.

            Params:
                key = record key
                value = record value; added if `this.outer.keys_only` is false

            Returns:
                result of adding the record to the batch

        ***********************************************************************/

        private RecordBatcher.AddResult addToBatch ( cstring key, cstring value )
        {
            if ( this.outer.keys_only )
                return this.outer.batcher.add(key);
            else
                return this.outer.batcher.add(key, value);
        }

        /***********************************************************************

            Sends a batch of records to the client.

        ***********************************************************************/

        private void sendBatch ( )
        {
            this.outer.batcher.compress(
                *(cast(ubyte[]*)this.outer.compressed_batch));

            if ( this.outer.compressed_batch.length == 0 )
                return; // Nothing in the batch

            this.outer.resources.request_event_dispatcher.send(this.fiber,
                ( RequestOnConnBase.EventDispatcher.Payload payload )
                {
                    payload.addConstant(MessageType.RecordBatch);
                    payload.addArray(*this.outer.compressed_batch);
                }
            );
        }
    }

    /***************************************************************************

        Fiber which handles:
            1. Reading control messages from the client.
            2. Sending an ACK message back (the client relies on ACKs to
               re-enable the user-facing controller).
            3. Controlling the writer fiber, as appropriate, to carry out the
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
                        break;
                    case Resume:
                        this.outer.writer.suspender.resumeIfSuspended();
                        break;
                    case Stop:
                        stopped = true;

                        // End the writer fiber. The request is finished.
                        this.outer.resources.request_event_dispatcher.abort(
                            this.outer.writer.fiber);
                        break;
                    default:
                        assert(false);
                }
            }
            while ( !stopped );
        }
    }
}

/// Static module logger
static private Logger log;

static this ( )
{
    log = Log.lookup("dhtproto.node.neo.request.GetAll");
}
