/*******************************************************************************

    DHT channel mirror helper.

    Abstract helper class that reads records from a DHT channel as they are
    modified. A mirror reads using two techniques:
        1. A DHT Listen request to receive records as they are modified.
        2. A periodically activated DHT GetAll request to ensure that the Listen
           request does not miss any records due to connection errors, etc.

    The receiveRecord method is abstract and must be implemented by the user.

    Copyright:
        Copyright (c) 2018 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.helper.Mirror;

import ocean.transition;

import swarm.client.request.notifier.IRequestNotification;

import dhtproto.client.DhtClient;
import dhtproto.client.legacy.internal.helper.mirror.model.MirrorBase;

/*******************************************************************************

    Channel mirror abstract helper class.

    Template params:
        Dht = type of DHT client (must be derived from DhtClient and contain the
            RequestScheduler plugin)

*******************************************************************************/

abstract public class Mirror ( Dht : DhtClient ) : MirrorBase!(Dht)
{
    import ocean.util.log.Logger;
    import ocean.text.convert.Formatter;
    import swarm.Const : NodeItem;
    import dhtproto.util.Verify;

    /// Core functionality shared by Listen and GetAll handlers.
    private final class SingleNodeRequest
    {
        /// Enum defining the state of the request.
        private enum State
        {
            None,
            Assigned,
            Scheduled,
            Running
        }

        /// State of the request.
        private State state = State.None;

        /// Logger for this request.
        private Logger log;

        /// Node that this request is communicating with.
        private NodeItem node;

        /***********************************************************************

            Constructor.

            Params:
                id = name / identifier of request, used for logging
                node = node address/port

        ***********************************************************************/

        public this ( cstring id, NodeItem node )
        {
            this.log = Log.lookup(format("Mirror.{} on {}:{} / {}", id,
                node.Address, node.Port, this.outer.channel_));
            this.node = node;
        }

        /***********************************************************************

            Starts the request, if it is not alrady running (or scheduled).

            Params:
                Rq = type of request
                rq = request object
                start_in_ms = milliseconds delay before assigning request. (If
                    0, assign immediately.)

        ***********************************************************************/

        public void start ( Rq ) ( Rq rq, uint start_in_ms = 0 )
        {
            if ( this.state != this.state.None )
            {
                this.log.info("Already {}ed; not re{}ing.",
                    this.state == this.state.Assigned ? "assign" : "schedul",
                    start_in_ms == 0 ? "assign" : "schedul");
                return;
            }

            if ( start_in_ms == 0 )
            {
                this.log.info("Starting.");
                this.outer.dht.assign(rq);
                this.state = State.Assigned;
            }
            else
            {
                this.log.info("Starting in {}ms.", start_in_ms);
                this.outer.dht.schedule(rq, start_in_ms);
                this.state = State.Scheduled;
            }
        }

        /***********************************************************************

            Resets the internal state. Should be called when the request
            finishes.

        ***********************************************************************/

        public void finished ( )
        {
            this.state = State.None;
        }

        /***********************************************************************

            Handles the state change from Assigned / Schedulued -> Running.
            Should be called when the request receives a record. (The API of the
            GetAll and Mirror requests do not provide any other way of telling
            when a request has been successfully established.)

        ***********************************************************************/

        public void receivedRecord ( )
        {
            if ( this.state == State.Running )
                return;

            verify(this.state == State.Assigned ||
                this.state == State.Scheduled);

            this.state = State.Running;
            log.info("Started receiving data.");
        }
    }

    /// Single-node Listen request handler.
    private class Listen
    {
        /// Core single-node request functionality.
        private SingleNodeRequest core;

        /***********************************************************************

            Constructor.

            Params:
                node = node address/port

        ***********************************************************************/

        public this ( NodeItem node )
        {
            this.core = new SingleNodeRequest("Listen", node);
        }

        /***********************************************************************

            Starts the request.

            Params:
                start_in_ms = milliseconds delay before assigning request. (If
                    0, assign immediately.)

        ***********************************************************************/

        public void start ( uint start_in_ms = 0 )
        {
            auto rq = this.outer.dht.listen(this.outer.channel_,
                &this.receiveRecord, &this.notifier).node(this.core.node);

            this.core.start(rq, start_in_ms);
        }

        /***********************************************************************

            Listen callback. Receives a value from the DHT.

            Params:
                key = record key
                value = record value

        ***********************************************************************/

        private void receiveRecord ( Dht.RequestContext, in char[] key,
            in char[] value )
        {
            this.core.receivedRecord();
            this.outer.receiveRecord(key, value, true);
        }

        /***********************************************************************

            Request notifier callback.

            Params:
                info = object containing notification information

        ***********************************************************************/

        private void notifier ( IRequestNotification info )
        {
            this.core.log.trace("{}", info.message(this.outer.dht.msg_buf));

            if ( this.outer.user_notifier !is null )
                this.outer.user_notifier(info);

            if ( info.type == info.type.Finished )
            {
                this.core.finished();

                // No need to check `info.succeeded` -- a Listen request can
                // never end cleanly.
                this.outer.error(info);
                this.core.log.error("{}. Retrying in {}ms.",
                    info.message(this.outer.dht.msg_buf),
                    this.outer.retry_time_ms);
                this.start(this.outer.retry_time_ms);
            }
        }
    }

    /// Single-node GetAll request handler.
    private class GetAll
    {
        /// Core single-node request functionality.
        private SingleNodeRequest core;

        /// Has this request succeeded at least once this cycle? (A cycle is
        /// defined as the period between the GetAll requests starting and all
        /// of them succeeding at least once.)
        private bool succeeded_;

        /// Reschedule once finished?
        public bool one_shot;

        /***********************************************************************

            Constructor.

            Params:
                node = node address/port

        ***********************************************************************/

        public this ( NodeItem node )
        {
            this.core = new SingleNodeRequest("GetAll", node);
        }

        /***********************************************************************

            Starts the request.

            Params:
                start_in_ms = milliseconds delay before assigning request. (If
                    0, assign immediately.)

        ***********************************************************************/

        public void start ( uint start_in_ms = 0 )
        {
            auto rq = this.outer.dht.getAll(this.outer.channel_,
                &this.receiveRecord, &this.notifier).node(this.core.node);

            this.core.start(rq, start_in_ms);
        }

        /***********************************************************************

            Returns:
                true if the request has finished successfully at least once this
                cycle

        ***********************************************************************/

        public bool succeeded ( )
        {
            return this.succeeded_;
        }

        /***********************************************************************

            Called at the start of a new cycle (i.e. when `succeeded_` is true
            for all active instances).

        ***********************************************************************/

        public void newCycle ( )
        {
            this.succeeded_ = false;
        }

        /***********************************************************************

            GetAll callback. Receives a value from the DHT.

            Params:
                key = record key
                value = record value

        ***********************************************************************/

        private void receiveRecord ( Dht.RequestContext, in char[] key,
            in char[] value )
        {
            this.core.receivedRecord();
            this.outer.receiveRecord(key, value, false);
        }

        /***********************************************************************

            Request notifier callback.

            Params:
                info = object containing notification information

        ***********************************************************************/

        private void notifier ( IRequestNotification info )
        {
            this.core.log.trace("{}", info.message(this.outer.dht.msg_buf));

            if ( this.outer.user_notifier !is null )
                this.outer.user_notifier(info);

            if ( info.type == info.type.Finished )
            {
                this.core.finished();

                if ( info.succeeded )
                {
                    this.succeeded_ = true;
                    this.outer.getAllSucceeded();

                    // If not doing a one-shot fill, schedule the GetAll again.
                    if ( !this.one_shot )
                        this.start(this.outer.update_time_ms);
                    this.one_shot = false;
                }
                else
                {
                    this.outer.error(info);
                    this.core.log.error("{}. Retrying in {}ms.",
                        info.message(this.outer.dht.msg_buf),
                        this.outer.retry_time_ms);
                    this.start(this.outer.retry_time_ms);
                }
            }
        }
    }

    /// User-provided request notifier.
    private Dht.RequestNotification.Callback user_notifier;

    /// Listen requests; one per DHT node.
    private Listen[NodeItem] listens;

    /// GetAll requests; one per DHT node.
    private GetAll[NodeItem] get_alls;

    /***************************************************************************

        Constructor.

        Params:
            dht = dht client used to access dht
            channel = name of dht channel to mirror
            update_time_s = seconds to wait between successful GetAlls
            retry_time_s = seconds to wait between failed requests
            notifier = optional callback called for each notification

    ***************************************************************************/

    public this ( Dht dht, cstring channel, uint update_time_s,
        uint retry_time_s, scope Dht.RequestNotification.Callback notifier = null )
    {
        super(dht, channel, update_time_s, retry_time_s);
        this.user_notifier = notifier;
    }

    /***************************************************************************

        Assigns a Listen request.

    ***************************************************************************/

    override protected void assignListen ( )
    {
        this.allocateListens();

        foreach ( addr, listen; this.listens )
            listen.start();
    }

    /***************************************************************************

        Assigns a one-shot (i.e. non-repeating) GetAll request.

    ***************************************************************************/

    override protected void assignOneShotGetAll ( )
    {
        this.allocateGetAlls();

        foreach ( addr, get_all; this.get_alls )
        {
            get_all.one_shot = true;
            get_all.start();
        }
    }

    /***************************************************************************

        Assigns a GetAll request that will periodically repeat, once it has
        finished.

    ***************************************************************************/

    override protected void assignGetAll ( )
    {
        this.allocateGetAlls();

        foreach ( addr, get_all; this.get_alls )
        {
            get_all.one_shot = false;
            get_all.start();
        }
    }

    /***************************************************************************

        Schedules a GetAll request that will periodically repeat, once it has
        finished.

    ***************************************************************************/

    override protected void scheduleGetAll ( )
    {
        this.allocateGetAlls();

        foreach ( addr, get_all; this.get_alls )
        {
            get_all.one_shot = false;
            get_all.start(this.update_time_ms);
        }
    }

    /***************************************************************************

        Iterates over the set of nodes in the client's registry and creates one
        Listen object for each. If an instance alreafy exists for a node, it is
        not recreated.

    ***************************************************************************/

    private void allocateListens ( )
    {
        foreach ( node; this.dht.nodes )
        {
            auto addr = NodeItem(node.address, node.port);
            if ( !(addr in this.listens) )
                this.listens[addr] = new Listen(addr);
        }
    }

    /***************************************************************************

        Iterates over the set of nodes in the client's registry and creates one
        GetAll object for each. If an instance alreafy exists for a node, it is
        not recreated.

    ***************************************************************************/

    private void allocateGetAlls ( )
    {
        foreach ( node; this.dht.nodes )
        {
            auto addr = NodeItem(node.address, node.port);
            if ( !(addr in this.get_alls) )
                this.get_alls[addr] = new GetAll(addr);
        }
    }

    /***************************************************************************

        Called by GetAll.notifier when a GetAll request finishes successfully.
        If all GetAll instances have finished successfully at least once, calls
        fillFinished.

    ***************************************************************************/

    private void getAllSucceeded ( )
    {
        foreach ( addr, get_all; this.get_alls )
            if ( !get_all.succeeded() )
                return;

        this.fillFinished();

        // Reset the state of the getAll helpers so we start counting
        // towards next fillFinished call.
        foreach (get_all; this.get_alls)
            get_all.newCycle();
    }

    /***************************************************************************

        GetAll finished notification.

        The base class does nothing, but this method may be overridden by
        derived classes to implement special fill behaviour.

    ***************************************************************************/

    protected void fillFinished ( )
    {
    }

    /***************************************************************************

        Error notification. Called when a GetAll request finishes due to an
        error or a Listen request finishes (this is always due to an error).
        Note that the Mirror class already logs these events internally.

        The base class does nothing, but this method may be overridden by
        derived classes to implement special behaviour on errors.

        Params:
            info = request notification

    ***************************************************************************/

    protected void error ( Dht.RequestNotification info )
    {
    }
}

/// Mirror usage example
unittest
{
    // Construct epoll and DHT client instances
    auto epoll = new EpollSelectDispatcher;
    auto dht = new SchedulingDhtClient(epoll);

    // TODO: call dht.addNodes() and perform the DHT handshake
    // (ignored in this example, for simplicity, and because we don't want to
    // really connect to a DHT in a unittest)

    // Dummy concrete channel mirror class
    class ExampleMirror : Mirror!(SchedulingDhtClient)
    {
        static immutable UpdatePeriod = 60; // do a GetAll every 60 seconds
        static immutable RetryPeriod = 3; // retry failed requests after 3 seconds

        public this ( SchedulingDhtClient dht, cstring channel )
        {
            super(dht, channel, UpdatePeriod, RetryPeriod);
        }

        // Called by the super class each time an updated record is received by
        // either the Listen or the GetAll request.
        override protected void receiveRecord ( in char[] key, in char[] value,
            bool single )
        {
            // TODO: handle record update
        }

        // Called by the super class each time a GetAll request is completed.
        // Note that in error cases (for example, when one node of a DHT
        // consistently fails to respond to the GetAll) this method is *not*
        // called.
        override protected void fillFinished ( )
        {
            // TODO: implement any special logic required when a GetAll has
            // completed (optional -- you may not need this)
        }
    }

    // Construct channel mirror
    auto mirror = new ExampleMirror(dht, "test_channel");

    // Activate an updating fetch of all records as in the mirrored channel as
    // they're modified.
    mirror();

    // TODO: epoll.eventLoop();
}

version ( UnitTest )
{
    import ocean.io.select.EpollSelectDispatcher;
}
