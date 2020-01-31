/*******************************************************************************

    DHT channel mirror helper base class. Defines the basic API.

    API for a helper class that reads records from a DHT channel as they are
    modified. A mirror reads using two techniques:
        1. A DHT Listen request to receive records as they are modified.
        2. A periodically activated DHT GetAll request to ensure that the Listen
           request does not miss any records due to connection errors, etc.

    The actual request assignment and handling are abstract.

    Copyright:
        Copyright (c) 2011-2018 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.helper.mirror.model.MirrorBase;

import ocean.meta.types.Qualifiers;
import ocean.core.Verify;

import dhtproto.client.DhtClient;

/*******************************************************************************

    Channel mirror API abstract base class.

    Template params:
        Dht = type of DHT client (must be derived from DhtClient and contain the
            RequestScheduler plugin)

*******************************************************************************/

abstract public class MirrorBase ( Dht : DhtClient )
{
    /// This helper only works in conjunction with the request scheduler plugin,
    /// so we assert that that exists in the client.
    static assert(Dht.HasPlugin!(DhtClient.RequestScheduler),
        "MirrorBase requires a DHT client with the RequestScheduler plugin");

    /// DHT client used to access DHT.
    protected Dht dht;

    /// Name of DHT channel to mirror.
    protected istring channel_;

    /// Time (in milliseconds) to wait between successful GetAlls.
    public const(uint) update_time_ms;

    /// Time (in milliseconds) to wait between failed requests.
    public const(uint) retry_time_ms;

    /***************************************************************************

        Constructor.

        Params:
            dht = DHT client used to access DHT
            channel = name of DHT channel to mirror
            update_time_s = seconds to wait between successful GetAlls
            retry_time_s = seconds to wait between failed requests

    ***************************************************************************/

    public this ( Dht dht, cstring channel, uint update_time_s,
        uint retry_time_s )
    {
        this.dht = dht;
        this.channel_ = idup(channel);
        this.update_time_ms = update_time_s * 1_000;
        this.retry_time_ms = retry_time_s * 1_000;
    }

    /***************************************************************************

        Returns:
            Name of DHT channel being mirrored

    ***************************************************************************/

    public istring channel ()
    {
        return this.channel_;
    }

    /// Struct, passed to start(), describing the requests to start.
    public struct Setup
    {
        /// Enum describing the possible GetAll modes.
        public enum GetAllMode
        {
            /// Do not assign GetAll requests.
            None,
            /// Assign one GetAll request but do not repeat.
            OneShot,
            /// Repeatedly assign GetAlls, according to the specified update
            /// time.
            Repeating,
            /// Ditto, but assign the first immediately (no delay).
            RepeatingNow
        }

        /// Enum describing the possible Listen modes.
        public enum ListenMode
        {
            /// Do not assign Listen requests.
            None,
            /// Assign Listen requests (runs continuously).
            Continuous
        }

        /// The desired GetAll mode. (Defaults to a repeating GetAll.)
        GetAllMode get_all_mode = GetAllMode.Repeating;

        /// The desired Listen mode. (Defaults to a continuous Listen.)
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
        verify(setup.get_all_mode != setup.get_all_mode.None ||
            setup.listen_mode != setup.listen_mode.None,
            "It doesn't make any sense to start a channel mirror with no GetAll"
            ~ " and no Listen.");

        with ( Setup.GetAllMode ) switch ( setup.get_all_mode )
        {
            case OneShot:
                this.assignOneShotGetAll();
                break;

            case Repeating:
                this.scheduleGetAll();
                break;

            case RepeatingNow:
                this.assignGetAll();
                break;

            case None:
            default:
                break;
        }

        with ( Setup.ListenMode ) switch ( setup.listen_mode )
        {
            case Continuous:
                this.assignListen();
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

        Assigns a Listen request.

    ***************************************************************************/

    abstract protected void assignListen ( );

    /***************************************************************************

        Assigns a one-shot (i.e. non-repeating) GetAll request.

    ***************************************************************************/

    abstract protected void assignOneShotGetAll ( );

    /***************************************************************************

        Assigns a GetAll request that will periodically repeat, once it has
        finished.

    ***************************************************************************/

    abstract protected void assignGetAll ( );

    /***************************************************************************

        Schedules a GetAll request that will periodically repeat, once it has
        finished.

    ***************************************************************************/

    abstract protected void scheduleGetAll ( );

    /***************************************************************************

        Application user callback. Receives a value from the DHT.

        Params:
            key = record key
            value = record value
            single_value = flag indicating whether the record was received from
                a Listen request (true) or a GetAll request (false)

    ***************************************************************************/

    abstract protected void receiveRecord ( in char[] key, in char[] value,
        bool single_value );
}
