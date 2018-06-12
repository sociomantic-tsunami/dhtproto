/*******************************************************************************

    v0 GetAll request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.GetAll;

import swarm.neo.node.IRequestHandler;
import ocean.util.log.Logger;

/// ditto
public abstract class GetAllProtocol_v0 : IRequestHandler
{
    import swarm.neo.node.RequestOnConn;
    import swarm.neo.connection.RequestOnConnBase;
    import swarm.neo.request.RequestEventDispatcher;
    import swarm.neo.util.MessageFiber;
    import swarm.util.RecordBatcher;
    import dhtproto.common.GetAll;
    import dhtproto.node.neo.request.core.Mixins;
    import ocean.transition;
    import ocean.core.Verify;

    /***************************************************************************

        Mixin the initialiser and the connection and resources members.

    ***************************************************************************/

    mixin IRequestHandlerRequestCore!();

    /// Request event dispatcher.
    private RequestEventDispatcher request_event_dispatcher;

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
                (&this).matcher = search(cast(Const!(ubyte)[])filter);
                (&this).active = true;
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
            if ( (&this).active )
                return (&this).matcher.forward(cast(Const!(ubyte)[])value)
                    < value.length;
            else
                return true;
        }
    }

    /// Value filter.
    private ValueFilter filter;

    /// If true, the request should be started in the suspended state.
    bool start_suspended;

    /// Return value of startIteration() or continueIteration().
    private bool initialised_ok;

    /***************************************************************************

        Called by the connection handler immediately after the request code and
        version have been parsed from a message received over the connection.
        Allows the request handler to process the remainder of the incoming
        message, before the connection handler sends the supported code back to
        the client.

        Note: the initial payload is a slice of the connection's read buffer.
        This means that when the request-on-conn fiber suspends, the contents of
        the buffer (hence the slice) may change. It is thus *absolutely
        essential* that this method does not suspend the fiber. (This precludes
        all I/O operations on the connection.)

        Params:
            init_payload = initial message payload read from the connection

    ***************************************************************************/

    public void preSupportedCodeSent ( Const!(void)[] init_payload )
    {
        bool continuing;
        hash_t continue_from;
        cstring channel;
        Const!(void)[] value_filter;
        this.connection.event_dispatcher.message_parser.parseBody(init_payload,
            this.start_suspended, channel, continuing, continue_from,
            this.keys_only, value_filter);

        if ( continuing )
            this.initialised_ok = this.continueIteration(channel, continue_from);
        else
            this.initialised_ok = this.startIteration(channel);

        // Set up filtering.
        this.filter.init(value_filter);
    }

    /***************************************************************************

        Called by the connection handler after the supported code has been sent
        back to the client.

    ***************************************************************************/

    public void postSupportedCodeSent ( )
    {
        // Send status code
        this.connection.event_dispatcher.send(
            ( RequestOnConnBase.EventDispatcher.Payload payload )
            {
                payload.addCopy(this.initialised_ok
                    ? MessageType.Started : MessageType.Error);
            }
        );
        this.connection.event_dispatcher.flush();

        if ( !this.initialised_ok )
            return;

        // Acquire required resources.
        this.compressed_batch = this.resources.getVoidBuffer();
        this.batcher = this.resources.getRecordBatcher();

        // Start the two fibers which form the request handling logic.
        scope writer_ = new Writer;
        scope controller_ = new Controller;

        this.request_event_dispatcher.initialise(&this.resources.getVoidBuffer);

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

        if ( this.start_suspended )
            this.writer.suspender.requestSuspension();

        this.controller.fiber.start();
        this.writer.fiber.start();
        this.request_event_dispatcher.eventLoop(
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
            dg = called with the key and value of the next record, if available

        Returns:
            true if a record was passed to `dg` or false if the iteration is
            finished

    ***************************************************************************/

    abstract protected bool getNext (
        scope void delegate ( hash_t key, Const!(void)[] value ) dg );

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

        /// Fiber resume code used to resume DelayedSuspender.
        private static immutable ResumeAfterSuspension = 1;

        /***********************************************************************

            Constructor. Gets a fiber from the shared resources.

        ***********************************************************************/

        public this ( )
        {
            this.fiber = this.outer.resources.getFiber(&this.fiberMethod);
            this.suspender = DelayedSuspender(
                &this.outer.request_event_dispatcher,
                this.outer.connection.event_dispatcher,
                this.fiber, ResumeAfterSuspension);
        }

        /***********************************************************************

            Fiber method.

        ***********************************************************************/

        private void fiberMethod ( )
        {
            hash_t key;
            uint yield_counter;

            // Iterate over the channel and send each record to the client.
            bool more;
            do
            {
                more = this.outer.getNext(
                    ( hash_t key, Const!(void)[] value )
                    {
                        if ( !this.outer.filter.match(cast(cstring)value) )
                            return;

                        cstring key_slice = (cast(char*)&key)[0..key.sizeof];
                        auto add_result = this.addToBatch(key_slice,
                            cast(cstring)value);

                        // If suspended, wait until resumed.
                        this.suspender.suspendIfRequested();

                        with ( RecordBatcher.AddResult ) switch ( add_result )
                        {
                            case Added:
                                // Can add more data to the batch
                                break;
                            case BatchFull:
                                // New record does not fit into this batch, send
                                // it and add the record to the next batch
                                this.sendBatch();
                                add_result = this.addToBatch(key_slice,
                                    cast(cstring)value);
                                verify(add_result == Added);
                                break;
                            case TooBig:
                                // Impossible to fit the record even in empty batch
                                log.warn(
                                    "GetAll: Large record 0x{:x16} ({} bytes) skipped.",
                                    key, value.length);
                                break;
                            default:
                                assert(false, "Invalid AddResult in switch");
                        }
                    }
                );

                this.outer.request_event_dispatcher.periodicYield(
                    this.fiber, yield_counter, 10);
            }
            while ( more );

            // Handle the last pending batch at the end of the iteration (does
            // nothing if no records are pending)
            this.sendBatch();

            // The request is now finished. Inform client of this and ignore any
            // further incoming control messages.
            this.outer.has_ended = true;
            this.outer.request_event_dispatcher.send(this.fiber,
                ( RequestOnConnBase.EventDispatcher.Payload payload )
                {
                    payload.addCopy(MessageType.Finished);
                }
            );

            // Wait for ACK from client
            this.outer.request_event_dispatcher.receive(this.fiber,
                Message(MessageType.Ack));

            // It's no longer valid to handle control messages.
            this.outer.request_event_dispatcher.abort(
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

            this.outer.request_event_dispatcher.send(this.fiber,
                ( RequestOnConnBase.EventDispatcher.Payload payload )
                {
                    payload.addCopy(MessageType.RecordBatch);
                    payload.addArray(*this.outer.compressed_batch);
                }
            );
            // flush() does not suspend the fiber, so is safe to call in a
            // RequestEventDispatcher-managed request.
            this.outer.connection.event_dispatcher.flush();
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
                    this.outer.request_event_dispatcher.receive(
                        this.fiber,
                        Message(MessageType.Suspend), Message(MessageType.Resume),
                        Message(MessageType.Stop));

                if ( this.outer.has_ended )
                    continue;

                // Send ACK. The protocol guarantees that the client will not
                // send any further messages until it has received the ACK.
                this.outer.request_event_dispatcher.send(this.fiber,
                    ( RequestOnConnBase.EventDispatcher.Payload payload )
                    {
                        payload.addCopy(MessageType.Ack);
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
                        this.outer.request_event_dispatcher.abort(
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
