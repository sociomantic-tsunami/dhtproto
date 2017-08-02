/*******************************************************************************

    Dht channel mirror helper.

    Abstract helper class to receive a copy of all records in a dht channel as
    they are updated.

    Usage example below.

    Copyright:
        Copyright (c) 2011-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.helper.ChannelMirror;



/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import swarm.client.request.notifier.IRequestNotification;

import swarm.Const : NodeItem;

import dhtproto.client.DhtClient;

import dhtproto.client.legacy.internal.helper.GroupRequest;



/*******************************************************************************

    Channel mirror abstract base class. Reads records from a dht channel as they
    are modified. The mirror reads using two techniques:

        1. A dht Listen request to receive records as they are modified.
        2. A periodically activated dht GetAll request to ensure that the Listen
           request does not miss any records due to connection errors, etc.

    The mirror automatically retries any failed dht requests.

    Usage example:
        See documented unittest, below

    Template params:
        Dht = type of dht client (must be derived from DhtClient and contain the
            RequestScheduler plugin)

*******************************************************************************/

abstract public class ChannelMirror ( Dht : DhtClient )
{
    /***************************************************************************

        This helper only works in conjunction with the request scheduler plugin,
        so we assert that that exists in the client.

    ***************************************************************************/

    static assert(Dht.HasPlugin!(DhtClient.RequestScheduler),
        "ChannelMirror helper requires RequestScheduler plugin in client");


    /***************************************************************************

        Helper class to manage a dht Listen request across multiple nodes.

        Listen requests which finish (which can only happen due to an error) are
        restarted on a per-node basis.

    ***************************************************************************/

    private class ListenRequest : GroupRequest!(Dht.Listen)
    {
        /***********************************************************************

            Constructor. Calls the super constructor with a Listen request for
            with specified channel and callback.

            Params:
                notifier = optional callback called for each notification

        ***********************************************************************/

        public this ( Dht.RequestNotification.Callback notifier = null )
        {
            super(this.outer.dht.listen(this.outer.channel_,
                                        &this.outer.listenReceiveRecord, notifier));
        }


        /***********************************************************************

            Called when one request in the group is finished. The request is
            always retried for the node which finished.

            Params:
                info = object containing information about the request

            Returns:
                true to indicate that one of the grouped requests should be
                counted as finished

        ***********************************************************************/

        override protected bool oneFinished ( IRequestNotification info )
        {
            this.outer.error(info);

            // Internal client error
            if ( info.nodeitem == NodeItem.init )
            {
                super.request.allNodes();
            }
            // I/O or node error
            else
            {
                super.request.node = info.nodeitem;
            }
            this.reschedule();

            return true;
        }


        /***********************************************************************

            Reschedule this request.

        ***********************************************************************/

        protected void reschedule ( )
        {
            this.outer.dht.schedule(this, this.outer.retry_time_ms);
        }
    }


    /***************************************************************************

        Helper class to manage a dht GetAll request across multiple nodes.

        GetAll requests which finish with an error are retried on a per-node
        basis. When the GetAll requests for all dht nodes have finished
        successfully, the whole GetAll request is rescheduled.

    ***************************************************************************/

    private class GetAllRequest : GroupRequest!(Dht.GetAll)
    {
        /***********************************************************************

            Constructor. Calls the super constructor with a GetAll request for
            with specified channel and callback.

            Params:
                notifier = optional callback called for each notification

        ***********************************************************************/

        public this ( Dht.RequestNotification.Callback notifier = null )
        {
            super(this.outer.dht.getAll(this.outer.channel_,
                                        &this.outer.getAllReceiveRecord,
                                        notifier));
        }


        /***********************************************************************

            Called when one request in the group is finished. If the request
            failed it is retried for this node.

            Params:
                info = object containing information about the request

            Returns:
                true to indicate that one of the grouped requests should be
                counted as finished

        ***********************************************************************/

        override protected bool oneFinished ( IRequestNotification info )
        {
            if ( info.succeeded )
            {
                return true;
            }
            else
            {
                this.outer.error(info);

                // Internal client error
                if ( info.nodeitem == NodeItem.init )
                {
                    super.request.allNodes();
                }
                // I/O or node error
                else
                {
                    super.request.node = info.nodeitem; // reset in allFinished()
                }
                this.reschedule(this.outer.retry_time_ms);

                return false;
            }
        }


        /***********************************************************************

            Called when all requests in the group are finished. If this is not
            the initial cache fill (i.e. the fill() method), then the next
            GetAll is scheduled according to the setting in the config file.

        ***********************************************************************/

        override protected void allFinished ( )
        {
            super.request.allNodes();

            super.had_error = false;

            this.outer.fillFinished();

            if ( !this.outer.filling )
            {
                this.reschedule(this.outer.update_time_ms);
            }
        }


        /***********************************************************************

            Reschedule this request.

            Params:
                time_ms = milliseconds in the future to schedule the request

        ***********************************************************************/

        protected void reschedule ( uint time_ms )
        {
            this.outer.dht.schedule(this, time_ms);
        }
    }


    /***************************************************************************

        Listen and GetAll group request helper instances.

    ***************************************************************************/

    private ListenRequest listen;

    private GetAllRequest get_all;


    /***************************************************************************

        Dht client used to access dht.

    ***************************************************************************/

    protected Dht dht;


    /***************************************************************************

        Name of dht channel to mirror.

    ***************************************************************************/

    protected istring channel_;


    /***************************************************************************

        Time (in milliseconds) to wait between successful GetAlls.

    ***************************************************************************/

    public Const!(uint) update_time_ms;


    /***************************************************************************

        Time (in milliseconds) to wait between failed requests.

    ***************************************************************************/

    public Const!(uint) retry_time_ms;


    /***************************************************************************

        Flag set to true when performing the initial cache fill.

    ***************************************************************************/

    private bool filling;


    /***************************************************************************

        Constructor.

        Params:
            dht           = dht client used to access dht
            channel       = name of dht channel to mirror
            update_time_s = seconds to wait between successful GetAlls
            retry_time_s  = seconds to wait between failed requests
            notifier      = optional callback called for each notification

    ***************************************************************************/

    public this ( Dht dht, cstring channel,
                  uint update_time_s, uint retry_time_s,
                  Dht.RequestNotification.Callback notifier = null )
    {
        this.dht         = dht;
        this.channel_    = idup(channel);
        this.update_time_ms = update_time_s * 1_000;
        this.retry_time_ms  = retry_time_s * 1_000;

        this.listen  = this.new ListenRequest(notifier);
        this.get_all = this.new GetAllRequest(notifier);
    }


    /***************************************************************************

        Additional constructor for unittests, allowing custom request handler
        instances to be passed, in place of instances of the standard
        ListenRequest and GetAllRequest. (Note that these are passed as lazy
        arguments as their constructors rely on the channel member of the outer
        class (i.e. this) having been set -- they cannot be constructed before.)

        Params:
            dht           = dht client used to access dht
            channel       = name of dht channel to mirror
            update_time_s = seconds to wait between successful GetAlls
            retry_time_s  = seconds to wait between failed requests
            listen        = ListenRequest instance to use internally
            get_all       = GetAllRequest instance to use internally
            notifier      = optional callback called for each notification

    ***************************************************************************/

    version ( UnitTest )
    public this ( Dht dht, cstring channel,
                  uint update_time_s, uint retry_time_s,
                  lazy ListenRequest listen, lazy GetAllRequest get_all,
                  Dht.RequestNotification.Callback notifier = null )
    {
        this.dht         = dht;
        this.channel_    = idup(channel);
        this.update_time_ms = update_time_s * 1_000;
        this.retry_time_ms  = retry_time_s * 1_000;

        this.listen  = listen;
        this.get_all = get_all;
    }


    /***************************************************************************

        Returns:
            Name of dht channel to mirror.

    ***************************************************************************/

    public istring channel ()
    {
        return this.channel_;
    }

    /***************************************************************************

        Struct, passed to start(), describing the requests to start.

    ***************************************************************************/

    public struct Setup
    {
        /***********************************************************************

            Enum describing the possible GetAll modes.

        ***********************************************************************/

        public enum GetAllMode
        {
            None,           // do not assign GetAll requests
            OneShot,        // assign one GetAll request but do not repeat
            Repeating,      // repeatedly assign GetAlls, according to the
                            // specified update time
            RepeatingNow    // ditto, but assign the first immediately (no delay)
        }

        /***********************************************************************

            Enum describing the possible Listen modes.

        ***********************************************************************/

        public enum ListenMode
        {
            None,       // do not assign Listen requests
            Continuous  // assign Listen requests (runs continuously)
        }

        /***********************************************************************

            The desired GetAll mode. (Defaults to a repeating GetAll.)

        ***********************************************************************/

        GetAllMode get_all_mode = GetAllMode.Repeating;

        /***********************************************************************

            The desired Listen mode. (Defaults to a continuous Listen.)

        ***********************************************************************/

        ListenMode listen_mode = ListenMode.Continuous;
    }

    /***************************************************************************

        Assigns GetAll and/or Listen requests according to the specific setup.

        Params:
            setup = struct instance describing the requests to start (defaults
                to a repeating GetAll request and a continuous Listen)

    ***************************************************************************/

    public void start ( Setup setup = Setup.init )
    {
        assert(!(setup.get_all_mode == setup.get_all_mode.None &&
            setup.listen_mode == setup.listen_mode.None),
            "It doesn't make any sense to start the ChannelMirror with no GetAll"
            ~ " and no Listen.");

        this.filling = false;

        with ( Setup.GetAllMode ) switch ( setup.get_all_mode )
        {
            case OneShot:
                this.filling = true;
                this.dht.assign(this.get_all);
                break;

            case Repeating:
                this.dht.schedule(this.get_all, this.update_time_ms);
                break;

            case RepeatingNow:
                this.dht.assign(this.get_all);
                break;

            case None:
            default:
                break;
        }

        with ( Setup.ListenMode ) switch ( setup.listen_mode )
        {
            case Continuous:
                this.dht.assign(this.listen);
                break;

            case None:
            default:
                break;
        }
    }

    /***************************************************************************

        Assigns a GetAll request to fetch all records from the channel. When the
        GetAll has finished it is not rescheduled.

    ***************************************************************************/

    public void fill ( )
    {
        Setup s;
        s.get_all_mode = s.get_all_mode.OneShot;
        s.listen_mode = s.listen_mode.None;
        this.start(s);
    }

    /***************************************************************************

        Schedules a GetAll request and assigns a Listen request to fetch all
        records from the channel as they are updated. When the GetAll finishes
        it is rescheduled to happen again after the time specified in the ctor.

        This method is aliased as opCall.

        Params:
            now = if true, the GetAll is started immediately, otherwise it is
                scheduled to occur after the update time specified in the ctor

    ***************************************************************************/

    public void mirror ( bool now = true )
    {
        Setup s;
        s.get_all_mode =
            now ? s.get_all_mode.RepeatingNow : s.get_all_mode.Repeating;
        this.start(s);
    }

    public alias mirror opCall;

    /***************************************************************************

        Dht GetAll callback. Receives a value from the dht.

        Params:
            key = record key
            value = record value

    ***************************************************************************/

    private void getAllReceiveRecord ( Dht.RequestContext,
                                       in char[] key, in char[] value )
    {
        this.receiveRecord(key, value, false);
    }

    /***************************************************************************

        Dht Listen callback. Receives a value from the dht.

        Params:
            key = record key
            value = record value

    ***************************************************************************/

    private void listenReceiveRecord ( Dht.RequestContext,
                                       in char[] key, in char[] value )
    {
        this.receiveRecord(key, value, true);
    }

    /***************************************************************************

        Application user callback. Receives a value from the dht.

        Params:
            key = record key
            value = record value
            single_value = flag indicating whether the record was received from
                a Listen request (true) or a GetAll request (false)

    ***************************************************************************/

    abstract protected void receiveRecord ( in char[] key, in char[] value,
                                            bool single_value );


    /***************************************************************************

        Error notification. Called when one request in either the Listen or the
        GetAll group fails (see the respective oneFinished() methods).

        The base class does nothing, but this method may be overridden by
        derived classes to implement special error behaviour.

        Params:
            info = request notification

    ***************************************************************************/

    protected void error ( Dht.RequestNotification info )
    {
    }


    /***************************************************************************

        GetAll finished notification.

        The base class does nothing, but this method may be overridden by
        derived classes to implement special fill behaviour.

    ***************************************************************************/

    protected void fillFinished ( )
    {
    }
}

/// ChannelMirror usage example
unittest
{
    // Construct epoll and DHT client instances
    auto epoll = new EpollSelectDispatcher;
    auto dht = new SchedulingDhtClient(epoll);

    // TODO: call dht.addNodes() and perform the DHT handshake
    // (ignored in this example, for simplicity, and because we don't want to
    // really connect to a DHT in a unittest)

    // Dummy concrete channel mirror class
    class Mirror : ChannelMirror!(SchedulingDhtClient)
    {
        const UpdatePeriod = 60; // do a GetAll every 60 seconds
        const RetryPeriod = 3; // retry failed requests after 3 seconds

        public this ( SchedulingDhtClient dht, in char[] channel )
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
    auto mirror = new Mirror(dht, "test_channel");

    // Activate an updating fetch of all records as in the mirrored channel as
    // they're modified.
    mirror();

    // TODO: epoll.eventLoop()
}

version ( UnitTest )
{
    import ocean.core.Test;
    import ocean.io.select.EpollSelectDispatcher;
    import dhtproto.client.DhtClient;
    import ocean.text.convert.Formatter;


    /***************************************************************************

        Derived ChannelMirror class for testing which:
            * Does not reschedule requests upon error
            * Tracks the occurrences of different types of event:
                - calls to ChannelMirror.error()
                - exceptions thrown within ListenRequest.oneFinished()
                - exceptions thrown within GetAllRequest.oneFinished()
                - exceptions thrown within GetAllRequest.allFinished()
                - calls to ListenRequest.reschedule()
                - calls to GetAllRequest.reschedule()

    ***************************************************************************/

    private class CM : ChannelMirror!(SchedulingDhtClient)
    {
        public EpollSelectDispatcher epoll;
        public uint request_error;

        private class ExtendedListen : ListenRequest
        {
            public uint one_finished_threw;
            public uint rescheduled;

            this ( )
            {
                super();
            }

            override protected bool oneFinished ( IRequestNotification info )
            {
                try
                {
                    return super.oneFinished(info);
                }
                catch ( Exception e )
                {
                    this.one_finished_threw++;
                    throw e;
                }
            }

            // Instead of rescheduling, we just set a flag indicating that this
            // was requested. This is to avoid an endless loop in the unittest.
            override protected void reschedule ( )
            {
                this.rescheduled++;
            }
        }

        private class ExtendedGetAll : GetAllRequest
        {
            public uint one_finished_threw;
            public uint all_finished_threw;
            public uint rescheduled;

            this ( )
            {
                super();
            }

            override protected bool oneFinished ( IRequestNotification info )
            {
                try
                {
                    return super.oneFinished(info);
                }
                catch ( Exception e )
                {
                    this.one_finished_threw++;
                    throw e;
                }
            }

            override protected void allFinished ( )
            {
                try
                {
                    super.allFinished();
                }
                catch ( Exception e )
                {
                    this.all_finished_threw++;
                    throw e;
                }
            }

            // Instead of rescheduling, we just set a flag indicating that this
            // was requested. This is to avoid an endless loop in the unittest.
            override protected void reschedule ( uint time_ms )
            {
                this.rescheduled++;
            }
        }

        this ( )
        {
            this.epoll = new EpollSelectDispatcher;
            this.dht = new SchedulingDhtClient(this.epoll);
            super(this.dht, "channel", 1, 1, new ExtendedListen, new ExtendedGetAll);
        }

        override protected void receiveRecord ( in char[] key, in char[] value,
            bool single_value ) { }

        override protected void error ( SchedulingDhtClient.RequestNotification info )
        {
            this.request_error++;
        }
    }
}


/*******************************************************************************

    Check that a simple instantiation of the ChannelMirror template compiles.

*******************************************************************************/

unittest
{
    class CM : ChannelMirror!(SchedulingDhtClient)
    {
        this ( )
        {
            super(new SchedulingDhtClient(new EpollSelectDispatcher),
                "channel", 1, 1);
        }

        override protected void receiveRecord ( in char[] key, in char[] value,
            bool single_value ) { }
    }

    auto cm = new CM;
}


/*******************************************************************************

    Test mirror's behaviour upon starting a fill operation with a DHT client
    which has not performed a handshake. All assigned requests should fail with
    an internal error.

*******************************************************************************/

unittest
{
    void fillWithoutHandshake ( uint num_nodes )
    {
        mstring name;
        sformat(name, "Fill without handshake, {} nodes", num_nodes);
        auto t = new NamedTest(idup(name));

        auto cm = new CM;
        for ( ushort port = 1_000; port < num_nodes + 1_000; port++ )
        {
            cm.dht.addNode("127.0.0.1".dup, port);
        }

        cm.fill();
        cm.epoll.eventLoop();
        t.test!("==")(cm.request_error, num_nodes);

        auto listen = cast(CM.ExtendedListen)cm.listen;
        auto get_all = cast(CM.ExtendedGetAll)cm.get_all;
        t.test!("==")(listen.one_finished_threw, 0);
        t.test!("==")(listen.rescheduled, 0);
        t.test!("==")(get_all.one_finished_threw, 0);
        t.test!("==")(get_all.all_finished_threw, 0);
        t.test!("==")(get_all.rescheduled, num_nodes);
    }

    fillWithoutHandshake(1);
    fillWithoutHandshake(2);
    fillWithoutHandshake(10);
}


/*******************************************************************************

    Test mirror's behaviour upon starting a mirror operation with a DHT client
    which has not performed a handshake. All assigned requests should fail with
    an internal error.

*******************************************************************************/

unittest
{
    void mirrorWithoutHandshake ( uint num_nodes )
    {
        mstring name;
        sformat(name, "Mirror without handshake, {} nodes", num_nodes);
        auto t = new NamedTest(idup(name));

        auto cm = new CM;
        for ( ushort port = 1_000; port < num_nodes + 1_000; port++ )
        {
            cm.dht.addNode("127.0.0.1".dup, port);
        }

        cm.mirror();
        cm.epoll.eventLoop();
        t.test!("==")(cm.request_error, num_nodes * 2);

        auto listen = cast(CM.ExtendedListen)cm.listen;
        auto get_all = cast(CM.ExtendedGetAll)cm.get_all;
        t.test!("==")(listen.one_finished_threw, 0);
        t.test!("==")(listen.rescheduled, num_nodes);
        t.test!("==")(get_all.one_finished_threw, 0);
        t.test!("==")(get_all.all_finished_threw, 0);
        t.test!("==")(get_all.rescheduled, num_nodes);
    }

    mirrorWithoutHandshake(1);
    mirrorWithoutHandshake(2);
    mirrorWithoutHandshake(10);
}
