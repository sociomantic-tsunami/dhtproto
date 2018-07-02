/*******************************************************************************
    
    Provides global test client instance used from test cases to access
    the node.

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.DhtClient;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;
import ocean.util.log.Logger;

/*******************************************************************************

    Class that encapsulates fiber/epoll reference and provides
    functions to emulate blocking API for swarm DHT client.

*******************************************************************************/

class DhtClient
{
    import ocean.core.Enforce;
    import ocean.core.Verify;
    import ocean.core.Array : copy;
    import ocean.task.Task;
    import ocean.task.Scheduler;
    import ocean.task.util.Timer : wait;

    import swarm.client.plugins.ScopeRequests;
    import swarm.util.Hash;
    import Swarm = dhtproto.client.DhtClient;

    /***************************************************************************

        Helper class to perform a request and suspend the current task until the
        request is finished.

    ***************************************************************************/

    private final class TaskBlockingRequest
    {
        import ocean.io.select.protocol.generic.ErrnoIOException : IOError;
        import swarm.Const : NodeItem;

        /// Task instance to be suspended / resumed while the request is handled
        private Task task;

        /// Counter of the number of request-on-conns which are not finished.
        private uint pending;

        /// Flag per request-on-conn, set to true if it is queued. Used to
        /// ensure that pending is not incremented twice.
        private bool[NodeItem] queued;

        /// Set if an error occurs in any request-on-conn.
        private bool error;

        /// Stores the last error message.
        private mstring error_msg;

        /***********************************************************************

            Constructor. Sets this.task to the current task.

        ***********************************************************************/

        public this ( )
        {
            this.task = Task.getThis();
            verify(this.task !is null);
        }

        /***********************************************************************

            Should be called after assigning a request. Suspends the task until
            the request finishes and then checks for errors.

            Throws:
                if an error occurred while handling the request

        ***********************************************************************/

        public void wait ( )
        {
            if ( this.pending > 0 )
                this.task.suspend();
            enforce(!this.error, idup(this.error_msg));
        }

        /***********************************************************************

            DHT request notifier to pass to the request being assigned.

            Params:
                info = notification info

        ***********************************************************************/

        public void notify ( SwarmClient.RequestNotification info )
        {
            switch ( info.type )
            {
                case info.type.Queued:
                    this.queued[info.nodeitem] = true;
                    this.pending++;
                    break;

                case info.type.Started:
                    if ( !(info.nodeitem in this.queued) )
                        this.pending++;
                    break;

                case info.type.Finished:
                    if ( !info.succeeded )
                    {
                        info.message(this.error_msg);

                        if ( cast(IOError) info.exception )
                            this.outer.log.warn("Socket I/O failure : {}",
                                this.error_msg);
                        else
                            this.error = true;
                    }

                    if ( --this.pending == 0 && this.task.suspended() )
                        this.task.resume();
                    break;

                default:
            }
        }
    }

    /***************************************************************************

        Reference to common fakedht logger instance

    ***************************************************************************/

    private Logger log;

    /***************************************************************************

        Alias for type of the standard DHT client in swarm

    ***************************************************************************/

    alias Swarm.DhtClient SwarmClient;

    /***************************************************************************

        Shared DHT client instance

    ***************************************************************************/

    private SwarmClient swarm_client;

    /***************************************************************************

        Indicates successful DHT handshake for `this.swarm_client`

    ***************************************************************************/

    private bool handshake_ok;

    /**************************************************************************

        Creates DHT client using the task scheduler's epoll instance

    ***************************************************************************/

    public this ( )
    {
        this.log = Log.lookup("dhttest");

        static immutable max_connections = 2;
        this.swarm_client = new SwarmClient(theScheduler.epoll, max_connections);
    }

    /***************************************************************************

        Connects to the legacy port of the DHT node. The test Task is suspended
        until connection has succeeded.

        Params:
            port = DHT node legacy port

    ***************************************************************************/

    public void handshake ( ushort port )
    {
        this.swarm_client.addNode("127.0.0.1".dup, port);

        auto task = Task.getThis();
        verify(task !is null);

        bool finished;

        void handshake_cb (SwarmClient.RequestContext, bool ok)
        {
            finished = true;
            this.handshake_ok = ok;
            if ( task.suspended() )
                task.resume();
        }

        this.swarm_client.nodeHandshake(&handshake_cb, null);
        if ( !finished )
            task.suspend();

        enforce(this.handshake_ok, "Test DHT handshake failed");
    }

    /***************************************************************************

        Indicates that internal swarm client has completed successful DHT
        handshake exchange

    ***************************************************************************/

    public bool hasCompletedHandshake ( )
    {
        return this.handshake_ok;
    }

    /***************************************************************************

        Adds a (key, data) pair to the specified DHT channel

        Params:
            channel = name of DHT channel to which data should be added
            key = key with which to associate data
            data = data to be added to DHT

        Throws:
            upon empty record or request error (Exception.msg set to indicate error)

    ***************************************************************************/

    public void put ( cstring channel, hash_t key, cstring data )
    {
        scope tbr = new TaskBlockingRequest;

        cstring input ( SwarmClient.RequestContext context )
        {
            return data;
        }

        this.swarm_client.assign(
            this.swarm_client.put(channel, key, &input, &tbr.notify));
        tbr.wait();
    }

    /***************************************************************************

        Get the item from the specified channel and the specified key.

        Params:
            channel = name of dht channel from which an item should be read.
            key = the key to get the data from.

        Returns:
            The associated data.

        Throws:
            upon request error (Exception.msg set to indicate error

    ***************************************************************************/

    public mstring get ( cstring channel, hash_t key )
    {
        scope tbr = new TaskBlockingRequest;

        mstring result;

        void output ( SwarmClient.RequestContext context, in cstring value )
        {
            if (value.length)
                result.copy(value);
        }

        this.swarm_client.assign(
            this.swarm_client.get(channel, key, &output, &tbr.notify));
        tbr.wait();

        return result;
    }

    /***************************************************************************

        Removes an item with the specified key from the specified channel.

        Params:
            channel = name of dht channel from which the item should be removed.
            key = the key of the item to remove.

        Throws:
            upon request error (Exception.msg set to indicate error)

    ***************************************************************************/

    public void remove ( cstring channel, hash_t key )
    {
        scope tbr = new TaskBlockingRequest;

        this.swarm_client.assign(
            this.swarm_client.remove(channel, key, &tbr.notify));
        tbr.wait();
    }

    /***************************************************************************

        Check whether an item with the specified key exists in the specified
        channel.

        Params:
            channel = name of dht channel in which the item should be checked.
            key = the key of the item to check.

        Returns:
            true if the record exists

        Throws:
            upon request error (Exception.msg set to indicate error)

    ***************************************************************************/

    public bool exists ( cstring channel, hash_t key )
    {
        scope tbr = new TaskBlockingRequest;

        bool result;

        void output ( SwarmClient.RequestContext context, bool exists )
        {
            result = exists;
        }

        this.swarm_client.assign(
            this.swarm_client.exists(channel, key, &output, &tbr.notify));
        tbr.wait();

        return result;
    }

    /***************************************************************************

        Get the number of records and bytes in the specified channel.

        Params:
            channel = name of dht channel.
            records = receives the number of records in the channel
            bytes = receives the number of bytes in the channel

        Throws:
            upon request error (Exception.msg set to indicate error)

    ***************************************************************************/

    public void getChannelSize ( cstring channel, out ulong records,
        out ulong bytes )
    {
        scope tbr = new TaskBlockingRequest;

        void output ( SwarmClient.RequestContext context, in cstring address,
            ushort port, in cstring channel, ulong r, ulong b )
        {
            records += r;
            bytes += b;
        }

        this.swarm_client.assign(
            this.swarm_client.getChannelSize(channel, &output, &tbr.notify));
        tbr.wait();
    }

    /***************************************************************************

        Gets all items from the specified channel.

        Params:
            channel = name of dht channel from which items should be fetched

        Returns:
            the set of records fetched

        Throws:
            upon request error (Exception.msg set to indicate error)

    ***************************************************************************/

    public mstring[hash_t] getAll ( cstring channel )
    {
        scope tbr = new TaskBlockingRequest;

        bool hash_error;
        mstring[hash_t] result;

        void output ( SwarmClient.RequestContext context, in cstring key,
            in cstring value )
        {
            if (!isHash(key))
            {
                hash_error = true;
                return;
            }
            result[straightToHash(key)] = value.dup;
        }

        this.swarm_client.assign(
            this.swarm_client.getAll(channel, &output, &tbr.notify));
        tbr.wait();
        enforce(!hash_error, "Bad record hash received");

        return result;
    }

    /***************************************************************************

        Gets all items from the specified channel which contain the specified
        filter string.

        Params:
            channel = name of dht channel from which items should be fetched
            filter = string to search for in values

        Returns:
            the set of filtered records fetched

        Throws:
            upon request error (Exception.msg set to indicate error)

    ***************************************************************************/

    public mstring[hash_t] getAllFilter ( cstring channel, cstring filter )
    {
        scope tbr = new TaskBlockingRequest;

        bool hash_error;
        mstring[hash_t] result;

        void output ( SwarmClient.RequestContext context, in cstring key,
            in cstring value )
        {
            if (!isHash(key))
            {
                hash_error = true;
                return;
            }
            result[straightToHash(key)] = value.dup;
        }

        this.swarm_client.assign(
            this.swarm_client.getAll(channel, &output, &tbr.notify)
            .filter(filter));
        tbr.wait();
        enforce(!hash_error, "Bad record hash received");

        return result;
    }

    /***************************************************************************

        Gets all keys from the specified channel.

        Params:
            channel = name of dht channel from which keys should be fetched

        Returns:
            the set of keys fetched

        Throws:
            upon request error (Exception.msg set to indicate error)

    ***************************************************************************/

    public hash_t[] getAllKeys ( cstring channel )
    {
        scope tbr = new TaskBlockingRequest;

        bool hash_error;
        hash_t[] result;

        void output ( SwarmClient.RequestContext context, in cstring key )
        {
            if (!isHash(key))
            {
                hash_error = true;
                return;
            }
            result ~= straightToHash(key);
        }

        this.swarm_client.assign(
            this.swarm_client.getAllKeys(channel, &output, &tbr.notify));
        tbr.wait();
        enforce(!hash_error, "Bad record hash received");

        return result;
    }

    /***************************************************************************

        Removes the specified channel.

        Params:
            channel = name of dht channel to remove

        Throws:
            upon request error (Exception.msg set to indicate error)

    ***************************************************************************/

    public void removeChannel ( cstring channel )
    {
        scope tbr = new TaskBlockingRequest;

        this.swarm_client.assign(
            this.swarm_client.removeChannel(channel, &tbr.notify));
        tbr.wait();
    }

    /***************************************************************************

        Assigns a Listen request and waits until it starts being handled.

        Notes:
            1. The only way to stop a Listen request is to remove the channel
               being listened to.
            2. This method writes a single dummy record (with key 0xDEAD) to the
               listened channel and waits for it to be received by a listener as
               confirmation that is has started successfully. The record is then
               restored to its previous state (either re-written or removed).

        Params:
            channel = channel to listen on

    ***************************************************************************/

    public Listener startListen ( cstring channel )
    {
        static immutable hash_t key = 0xDEAD;

        auto listener = new Listener;

        this.swarm_client.assign(this.swarm_client.listen(channel,
            &listener.record, &listener.notifier));

        // FLAKY: As there is no notification when the Listen request has
        // started being handled by the node, it's possible that the dummy
        // record put (see below) will arrive before the Listen request is
        // registered with the channel to receive updates. Given the lack of
        // notification, it's impossible to write a non-flaky test for this.
        // In this circumstance, simply waiting 100ms after assigning the Listen
        // request -- while it could, in principle, still fail -- will massively
        // reduce flakiness.
        wait(100_000);

        auto original_value = this.get(channel, key);
        this.put(channel, key, "dummy_value"[]);

        while (!listener.data.length)
            listener.waitNextEvent();

        listener.data = null;

        if ( original_value.length )
            this.put(channel, key, original_value);
        else
            this.remove(channel, key);

        return listener;
    }

    /***************************************************************************

        Blocking wrapper on top of Listen request

    ***************************************************************************/

    public static class Listener
    {
        /***********************************************************************

            Indicates that listener has been terminated - most commonly,
            because there is no more channel to listen on

        ***********************************************************************/

        public bool finished = false;

        /***********************************************************************

            Set when an invalid key is received in record().

        ***********************************************************************/

        public bool hash_error = false;

        /***********************************************************************

            Read records get stored here as a simply key->value AA. When the
            test case has finished checking the received data, it must remove it
            from the AA, otherwise waitNextEvent() will always return
            immediately, without waiting.

        ***********************************************************************/

        public cstring[hash_t] data;

        /***********************************************************************

            Binds listener to current Task.

        ***********************************************************************/

        public this ( )
        {
            this.task = Task.getThis();
            verify(this.task !is null);
        }

        /***********************************************************************

            Returns when either data has been received by the Listen request or
            the channel being listened to has been removed. If neither of those
            things are immediately true, when the method is called, the bound
            task is suspended until one of them occurs. Thus, when this method
            returns, one of the following has happened:

                1. Data was already available (in this.data), so the task was
                   not suspended.
                2. The Listen request has finished, so the task was not
                   suspended.
                3. The task was suspended, new data arrived, and the task was
                   resumed. The new data is added to this.data, where it can be
                   read by the test case. When the test case has finished
                   checking the received data, it must remove it from the AA,
                   otherwise subsequent calls to waitNextEvent() will always
                   return immediately (case 1), without waiting.
                4. The task was suspended, the Listen request terminated due to
                   the channel being removed, and the task was resumed. It is
                   not possible to make further use of this instance.

        ***********************************************************************/

        public void waitNextEvent ( )
        {
            if ( this.finished || this.data.length )
                return;

            this.waiting = true;
            this.task.suspend();
            this.waiting = false;
        }

        /***********************************************************************

            Task that gets suspended when `waitNextEvent` is called.

        ***********************************************************************/

        private Task task;

        /***********************************************************************

            Set to true when this.task was suspended by waitNextEvent(). Used to
            decide whether to resume the task when an event occurs. (This
            instance is not necessarily the only thing controlling the task, so
            it must be sure to only resume the task when it was the one who
            suspended it originally.)

        ***********************************************************************/

        private bool waiting;

        /***********************************************************************

            Internal callback for storing new records

        ***********************************************************************/

        private void record ( SwarmClient.RequestContext c, in cstring key,
            in cstring value )
        {
            if (!isHash(key))
            {
                this.hash_error = true;
                return;
            }

            this.data[straightToHash(key)] = value.dup;

            if ( this.waiting )
                this.task.resume();
        }

        /***********************************************************************

            Internal callback for processing listener events

        ***********************************************************************/

        private void notifier ( SwarmClient.RequestNotification info )
        {
            if ( info.type == info.type.Finished )
            {
                this.finished = true;

                if ( this.waiting )
                    this.task.resume();
            }
        }
    }
}
