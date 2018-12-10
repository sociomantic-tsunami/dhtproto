/*******************************************************************************

    Implements very simple DHT storage based on built-in associative arrays.

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.Storage;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import ocean.core.Enforce;
import ocean.task.Task;
import ocean.task.Scheduler;

import swarm.node.storage.listeners.Listeners;

/*******************************************************************************

    DHT listener interface type. Requests that need to be notified of DHT
    channel changes must inherit from this type.

*******************************************************************************/

public alias IListenerTemplate!(cstring) DhtListener;

/*******************************************************************************

    Global storage used by all requests.

*******************************************************************************/

public DHT global_storage;

/*******************************************************************************

    Wraps channel name to to channel object AA in struct with extra convenience
    methods.

*******************************************************************************/

struct DHT
{
    /***************************************************************************

        channel name -> channel object AA

    ***************************************************************************/

    private Channel[istring] channels;

    /***************************************************************************

        Params:
            channel_name = channel name (id) to look for

        Returns:
            requested channel object if present, null otherwise

    ***************************************************************************/

    public Channel get (cstring channel_name)
    {
        auto channel = channel_name in (&this).channels;
        if (channel is null)
            return null;
        return *channel;
    }

    /***************************************************************************

        Params:
            channel_name = channel name (id) to look for

        Returns:
            requested channel object

        Throws:
            MissingChannelException if not present

    ***************************************************************************/

    public Channel getVerify ( cstring channel_name )
    {
        auto channel = channel_name in (&this).channels;
        enforce!(MissingChannelException)(channel !is null, idup(channel_name));
        return *channel;
    }

    /***************************************************************************

        Creates requested channel automatically if it wasn't found

        Params:
            channel_name = channel name (id) to look for

        Returns:
            requested channel object

    ***************************************************************************/

    public Channel getCreate (cstring channel_name)
    {
        auto channel = channel_name in (&this).channels;
        if (channel is null)
        {
            (&this).channels[idup(channel_name)] = new Channel;
            channel = channel_name in (&this).channels;
        }
        return *channel;
    }

    /***************************************************************************

        Removes specified channel from the storage

        Params:
            channel_name = channel name (id) to remove

    ***************************************************************************/

    public void remove (cstring channel_name)
    {
        auto channel = (&this).get(channel_name);
        if (channel !is null)
        {
            channel.listeners.trigger(DhtListener.Code.Finish, "");
            (&this).channels.remove(idup(channel_name));
        }
    }

    /***************************************************************************

        Empties all channels in the storage

    ***************************************************************************/

    public void clear ( )
    {
        auto names = (&this).channels.keys;
        foreach (name; names)
        {
            auto channel = (&this).getVerify(name);
            channel.data = null;
        }
    }

    /***************************************************************************

        Removes all data about registered listeners from channels

        Intended as a tool for clean restart, must not be called while node
        is active and serving requests.

    ***************************************************************************/

    public void dropAllListeners ( )
    {
        foreach (channel; (&this).channels)
        {
            channel.listeners = channel.new Listeners;
        }
    }

    /***************************************************************************

        Returns:
            All channels in the storage as a string array

    ***************************************************************************/

    public istring[] getChannelList ( )
    {
        istring[] result;

        foreach (key, value; (&this).channels)
            result ~= key;

        return result;
    }
}

/*******************************************************************************

    Wraps key -> value AA in a class with extra convenience methods. Class is
    chosen over a struct so that listeners can be initialized in constructor.

*******************************************************************************/

class Channel
{
    import ocean.core.Verify;
    import ocean.text.convert.Formatter;

    /***************************************************************************

        Defines a channel listener type which expects one argument for
        `trigger` method - changed record key

    ***************************************************************************/

    private class Listeners : IListeners!(cstring)
    {
        /***********************************************************************

            Number of listeners currently writing

        ***********************************************************************/

        private size_t sending_listeners;

        /***********************************************************************

            Caller task to resume when output is flushed

        ***********************************************************************/

        private Task caller;

        /***********************************************************************

            Suspends the caller task until all liseners which are currently
            sending data to the client are done (o.e. are back in the state of
            waiting for more data).

        ***********************************************************************/

        public void waitUntilFlushed ( )
        {
            if ( !this.sending_listeners )
                return;

            enforce(this.caller is null);
            this.caller = Task.getThis();
            enforce(this.caller !is null);

            this.caller.suspend();
            this.caller = null;
        }

        /***********************************************************************

            Indicates that a listener has finished sending data to the client.
            When all listeners have finished sending data, if a task was
            previously registered via waitUntilFlushed(), it is resumed.

        ***********************************************************************/

        public void listenerFlushed ( )
        {
            verify(this.sending_listeners > 0);
            this.sending_listeners--;

            if ( this.sending_listeners == 0 && (this.caller !is null) )
            {
                this.caller.resume();
            }
        }

        /***********************************************************************

            Returns:
                the number of registered listeners

        ***********************************************************************/

        public size_t length ( )
        {
            return this.listeners.length;
        }

        /***********************************************************************

            Tracks the number of listeners in the sending state, in addition to
            the base class' trigger_() behaviour.

        ***********************************************************************/

        override protected void trigger_ ( DhtListener.Code code, cstring key )
        {
            this.sending_listeners += this.listeners.length;
            super.trigger_(code, key);
        }
    }

    /***************************************************************************

        Alias to minimize bracket clutter in type declarations

    ***************************************************************************/

    private alias Const!(void)[] ValueType;

    /***************************************************************************

        Internal key -> value storage

    ***************************************************************************/

    private ValueType[istring] data;

    /***************************************************************************

        Requests (listeners) waiting to be notified about data changes in
        this channel. Storage implementation is responsible of calling
        `listeners.trigger(code, key)` each time something changes.

    ***************************************************************************/

    private Listeners listeners;

    /***************************************************************************

        Constructor

    ***************************************************************************/

    this ( )
    {
        this.listeners = new Listeners;
    }

    /***************************************************************************

        Returns:
            keys of all records in the channel as a string array

    ***************************************************************************/

    public istring[] getKeys ( )
    {
        istring[] result;

        foreach (key, value; this.data)
            result ~= key;

        return result;
    }

    /***************************************************************************

        Params:
            key = record key to look for

        Returns:
            requested record value if present, null array otherwise

    ***************************************************************************/

    public ValueType get ( cstring key )
    {
        auto value = key in this.data;
        return (value is null) ? null : *value;
    }

    /***************************************************************************

        Ditto

    ***************************************************************************/

    public ValueType get ( hash_t key )
    {
        mstring key_str;
        sformat(key_str, "{:x16}", key);
        return this.get(key_str);
    }

    /***************************************************************************

        Params:
            key = record key to look for

        Returns:
            requested record value

        Throws:
            MissingRecordException if not present

    ***************************************************************************/

    public ValueType getVerify ( cstring key )
    {
        auto value = key in this.data;
        enforce!(MissingRecordException)(value !is null, idup(key));
        return *value;
    }

    /***************************************************************************

        Ditto

    ***************************************************************************/

    public ValueType getVerify ( hash_t key )
    {
        mstring key_str;
        sformat(key_str, "{:x16}", key);
        return this.getVerify(key_str);
    }

    /***************************************************************************

        Adds a new record or modifies an old one

        If called inside a task context, will suspend calling task until
        registered DHT listeners will receive the value that was pushed.

        Params:
            key = record key to write to
            value = new record value

    ***************************************************************************/

    public void put ( cstring key, ValueType value )
    {
        this.data[key] = value;
        this.listeners.trigger(Listeners.Listener.Code.DataReady, key);
        if (Task.getThis() !is null)
            this.listeners.waitUntilFlushed();
    }

    /***************************************************************************

        Ditto

    ***************************************************************************/

    public void put ( hash_t key, ValueType value )
    {
        mstring key_str;
        sformat(key_str, "{:x16}", key);
        this.put(key_str, value);
    }

    /***************************************************************************

        Counts total size taken by all records

        Params:
            records = will contain total record count
            bytes = will contain total record size

    ***************************************************************************/

    public void countSize (out size_t records, out size_t bytes)
    {
        records = this.data.length;
        foreach (key, value; this.data)
            bytes += value.length;
    }

    /***************************************************************************

        Params:
            key = key of the record to remove

        Returns:
            true if the record existed or false if it did not

    ***************************************************************************/

    public bool remove ( cstring key )
    out ( existed )
    {
        assert((key in this.data) is null);
    }
    body
    {
        auto existed = (key in this.data) !is null;
        this.data.remove(idup(key));

        this.listeners.trigger(Listeners.Listener.Code.Deletion, key);
        if (Task.getThis() !is null)
            this.listeners.waitUntilFlushed();

        return existed;
    }

    /***************************************************************************

        Ditto

    ***************************************************************************/

    public bool remove ( hash_t key )
    {
        mstring key_str;
        sformat(key_str, "{:x16}", key);
        return this.remove(key_str);
    }

    /***************************************************************************

        Registers a listener with the channel. The dataReady() method of the
        given listener may be called when data is put to the channel.

        Params:
            listener = consumer to notify when data is ready

    ***************************************************************************/

    public void register ( DhtListener listener )
    {
        this.listeners.register(listener);
    }

    /***************************************************************************

        Unregisters a listener from the channel.

        Params:
            listener = listener to stop notifying when data is ready

    ***************************************************************************/

    public void unregister ( DhtListener listener )
    {
        this.listeners.unregister(listener);
    }

    /***************************************************************************

        Indicates that a listener has finished sending data to the client. When
        all listeners have finished sending data, if a task was previously
        registered via this.listeners.waitUntilFlushed(), it is resumed.

    ***************************************************************************/

    public void listenerFlushed ( )
    {
        this.listeners.listenerFlushed();
    }

    /***************************************************************************

        Returns:
            the number of listeners that are registered with the channel

    ***************************************************************************/

    public size_t registered_listeners ( )
    {
        return this.listeners.length;
    }

    /***************************************************************************

        Returns:
            the number of listeners which are currently sending data

    ***************************************************************************/

    public size_t sending_listeners ( )
    {
        return this.listeners.sending_listeners;
    }
}

/*******************************************************************************

    Exception that indicates invalid operation with non-existent channel

*******************************************************************************/

class MissingChannelException : Exception
{
    this ( istring name, istring file = __FILE__, int line = __LINE__ )
    {
        super("Trying to work with non-existent channel " ~ name, file, line);
    }
}

/*******************************************************************************

    Exception that indicates invalid operation with non-existent record

*******************************************************************************/

class MissingRecordException : Exception
{
    this ( istring key, istring file = __FILE__, int line = __LINE__ )
    {
        super("Trying to work with non-existent record (key = " ~ key ~ ")",
            file, line);
    }
}

version ( UnitTest )
{
    import ocean.core.Test;
}

/*******************************************************************************

    Test that the enforce in Listeners.waitUntilFlushed() (that the method is
    not already waiting) does not fire.

*******************************************************************************/

unittest
{
    DHT dht;
    auto channel = dht.getCreate("test_channel");

    // Fake listener class, required by Channel.register().
    class FakeListener : DhtListener
    {
        size_t count;

        override void trigger ( Code, cstring )
        {
            channel.listenerFlushed();
            ++count;
        }
    }

    // Register a listener with a test DHT channel.
    auto listener = new FakeListener;
    channel.register(listener);

    // Define a task that tries to put one value as soon as event
    // loop is started
    class TestTask : Task
    {
        bool error;

        override public void run ( )
        {
            theScheduler.processEvents();

            try
            {
                channel.put("key", "value");
            }
            catch ( Exception e )
            {
                error = true;
            }
        }
    }

    initScheduler(SchedulerConfiguration.init);

    auto task1 = new TestTask;
    auto task2 = new TestTask;

    // shedule two identical tasks simulaneously
    theScheduler.schedule(task1);
    theScheduler.schedule(task2);

    theScheduler.eventLoop();

    // ensure two writer tasks don't interfere with each other
    test(!task1.error);
    test(!task2.error);

    // ensures total amount of records received equals to the amount added
    test(listener.count == 2);
}
