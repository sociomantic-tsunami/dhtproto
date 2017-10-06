/*******************************************************************************

    DHT node emulation environment

    Extends turtle environment node base with methods to directly inspect and
    modify the contents of the fake node.

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module turtle.env.Dht;

import ocean.transition;

import turtle.env.model.Node;

import fakedht.DhtNode;
import fakedht.Storage;

import ocean.core.Test;
import ocean.task.Scheduler;
import ocean.task.util.Timer;
import ocean.text.convert.Formatter;

/*******************************************************************************

    Aliases to exceptions thrown on illegal operations with dht storage

    Check `Throws` DDOC sections of methods in this module to see when
    exactly these can be thrown.

*******************************************************************************/

public alias fakedht.Storage.MissingChannelException MissingChannelException;
public alias fakedht.Storage.MissingRecordException MissingRecordException;

/*******************************************************************************

    Returns:
        singleton DHT instance (must first be initialised by calling
        Dht.initialize())

*******************************************************************************/

public Dht dht()
in
{
    assert (_dht !is null, "Must call `Dht.initialize` first");
}
body
{
    return _dht;
}

private Dht _dht;

/*******************************************************************************

    The Dht class encapsulates creation/startup of fake DHT node and most
    common operations on data it stores. Only one Dht object is allowed to
    be created.

*******************************************************************************/

public class Dht : Node!(DhtNode, "dht")
{
    import dhtproto.client.legacy.DhtConst;
    import Hash = swarm.util.Hash;

    import ocean.core.Enforce;

    import ocean.util.serialize.contiguous.Contiguous;
    import ocean.util.serialize.contiguous.Serializer;
    import ocean.util.serialize.contiguous.Deserializer;
    import ocean.util.serialize.contiguous.MultiVersionDecorator;
    import ocean.util.serialize.Version;

    import ocean.text.convert.Integer_tango;

    /***************************************************************************

        Prepares DHT singleton for usage from tests

    ***************************************************************************/

    public static void initialize ( )
    {
        if ( !_dht )
            _dht = new Dht();
    }

    /***************************************************************************

        Adds a (key, data) pair to the specified DHT channel

        Params:
            channel = name of DHT channel to which data should be added
            key = key with which to associate data
            data = struct containing data to be added to DHT

    ***************************************************************************/

    public void put ( T ) ( cstring channel, hash_t key, T data )
    {
        void[] serialized_data;

        static if (is(T : cstring))
            serialized_data = data.dup;
        else static if (is(T == struct))
        {
            static if (Version.Info!(T).exists)
                (new VersionDecorator).store(data, serialized_data);
            else
                Serializer.serialize(data, serialized_data);
        }
        else
            static assert (false, "Only struct and string values are supported");

        enforce(serialized_data.length, "Cannot put empty data to the dht!");

        // dht protocol defines keys as strings
        // but env.Dht tries to mimic swarm client API which uses hash_t
        char[Hash.HashDigits] str_key;
        Hash.toHexString(key, str_key);

        global_storage.getCreate(channel).put(str_key.dup, serialized_data);
    }

    unittest
    {
        struct NotVersioned { int x; }
        struct Versioned { const StructVersion = 0; int x; }

        // ensures compilation
        void stub ( )
        {
            dht.put("abc", 0xABC, NotVersioned.init);
            dht.put("abc", 0xABC, Versioned.init);
            dht.put("abc", 0xABC, "data");
        }
    }

    /***************************************************************************

        Get the item from the specified channel and the specified key.

        Template params:
            T = The type to deserialize the item to. Defaults to mstring.

        Params:
            channel = name of dht channel from which an item should be popped.
            key = the key to get the data from.

        Throws:
            MissingChannelException if channel does not exist
            MissingRecordException if record with requested key does not exist

        Returns:
            The associated data.

    ***************************************************************************/

    public T get ( T = mstring ) ( cstring channel, size_t key )
    {
        // dht protocol defines keys as strings
        // but env.Dht tries to mimic swarm client API which uses hash_t
        char[Hash.HashDigits] str_key;
        Hash.toHexString(key, str_key);

        auto data = global_storage.getVerify(channel).getVerify(str_key[]);

        static if (is(T : cstring))
            return cast(T) data.dup;
        else static if (is(T == struct))
        {
            enforce(data.length != 0);
            Contiguous!(T) tmp;

            static if (Version.Info!(T).exists)
                return *(new VersionDecorator).loadCopy(data, tmp).ptr;
            else
                return *Deserializer.deserialize(data, tmp).ptr;
        }
        else
            static assert (false, "Only struct and string values are supported");
    }

    /***************************************************************************

        Stored DHT record with strongly typed value

    ***************************************************************************/

    struct KeyValuePair ( Value )
    {
        hash_t key;
        Value value;
    }

    /***************************************************************************

        Get all keys for record stored in the channel as an array

        Params:
            channel = name of the channel to get data from

        Returns:
            array of key hashes

    ***************************************************************************/

    public hash_t[] getAllKeys ( cstring channel )
    {
        auto string_keys = global_storage.getVerify(channel).getKeys();
        hash_t[] result;
        foreach (key; string_keys)
            result ~= toUlong(key, 16);
        return result;
    }

    /***************************************************************************

        Get all data stored in the channel as key-value record array

        Params:
            channel = name of the channel to get data from

        Template_Params:
            T = type of value to expect

        Returns:
            array of key-value structs

    ***************************************************************************/

    public KeyValuePair!(T)[] getAll ( T = mstring ) ( cstring channel )
    {
        KeyValuePair!(T)[] result;

        auto keys = this.getAllKeys(channel);

        foreach (key; keys)
        {
            KeyValuePair!(T) record;
            record.key = key;
            record.value = this.get!(T)(channel, key);
            result ~= record;
        }

        return result;
    }

    /***************************************************************************

        Packs together channel size and length data

    ***************************************************************************/

    struct ChannelSize
    {
        size_t records, bytes;
    }

    /***************************************************************************

        Gets the size of the specified DHT channel (in number of records and
        in bytes) and returns it

        Params:
            channel = name of DHT channel to get size of

        Returns:
            Size of specified channel

    ***************************************************************************/

    public ChannelSize getSize ( cstring channel)
    {
        ChannelSize result;
        if (auto channel_obj = global_storage.get(channel))
            channel_obj.countSize(result.records, result.bytes);
        return result;
    }

    /***************************************************************************

        Waits either until specified record changes or timeout happens.

        Helper for a pattern commonly present in tests for applications writing
        to DHT.

        Params:
            channel = DHT channel to lookup
            key = DHT record key to lookup
            timeout = limit of time to wait (seconds)
            check_interval = how often to poll for changes (seconds)

        Throws:
            TestException if timeout has been hit

    ***************************************************************************/

    public void expectRecordChange ( cstring channel, hash_t key,
        double timeout = 1.0, double check_interval = 0.05 )
    {
        char[Hash.HashDigits] str_key;
        Hash.toHexString(key, str_key);

        // it is ok to retrieve/cache the watched record old value right
        // in this method because test task is still in control and fakedht
        // won't be able to handle request from tested application even if
        // it attempts to modify the record before this method is called
        auto original = global_storage.getCreate(channel).get(str_key);
        auto total_wait = 0.0;

        do
        {
            .wait(cast(uint) (check_interval * 1_000_000));
            total_wait += check_interval;

            auto current = global_storage.getCreate(channel).get(str_key);
            if (original != current)
                return;
        }
        while (total_wait < timeout);

        throw new TestException(.format(
            "No change for record {} in channel '{}' during {} seconds",
            str_key,
            channel,
            timeout
        ));
    }

    /***************************************************************************

        Waits until specified condition becomes true for certain record.

        Contrary to `expectRecordChange` this method doesn't keep track of old
        state of the record and uses supplied predicate delegate as only
        termination condition.

        Params:
            channel = DHT channel to lookup
            key = DHT record key to lookup
            dg = predicate to run on polled record data
            timeout = limit of time to wait (seconds)
            check_interval = how often to poll for changes (seconds)

        Throws:
            TestException if timeout has been hit

    ***************************************************************************/

    public void expectRecordCondition ( cstring channel, hash_t key,
        bool delegate ( in void[] record ) dg,
        double timeout = 1.0, double check_interval = 0.05 )
    {
        char[Hash.HashDigits] str_key;
        Hash.toHexString(key, str_key);

        auto total_wait = 0.0;

        do
        {
            .wait(cast(uint) (check_interval * 1_000_000));
            total_wait += check_interval;

            auto current = global_storage.getCreate(channel).get(str_key);
            if (dg(current))
                return;
        }
        while (total_wait < timeout);

        throw new TestException(.format(
            "Expected condition was not hit for record {} in channel '{}' " ~
                "during {} seconds",
            str_key,
            channel,
            timeout
        ));
    }

    /***************************************************************************

        Creates a fake node at the specified address/port.

        Params:
            node_item = address/port

    ***************************************************************************/

    override protected DhtNode createNode ( NodeItem node_item )
    {
        auto epoll = theScheduler.epoll();

        auto node = new DhtNode(node_item, epoll);
        node.register(epoll);

        return node;
    }

    /***************************************************************************

        Returns:
            address/port on which node is listening

    ***************************************************************************/

    override public NodeItem node_item ( )
    {
        assert(this.node);
        return this.node.node_item;
    }

    /***************************************************************************

        Stops the fake DHT service. The node may be started again on the same
        port via restart().

    ***************************************************************************/

    override protected void stopImpl ( )
    {
        this.node.stopListener(theScheduler.epoll);
        this.node.shutdown();
    }

    /***************************************************************************

        Removes all data from the fake node service.

    ***************************************************************************/

    override public void clear ( )
    {
        global_storage.clear();
    }

    /***************************************************************************

        Removes all channels and terminates all active Listen requests.

        This method needs to be called instead of `clear` if application
        is restarted between tests to ensure no requests remain hanging. In all
        other cases prefer `clear`.

    ***************************************************************************/

    override public void reset ( )
    {
        foreach (channel; global_storage.getChannelList())
            global_storage.remove(channel);
    }

    /***************************************************************************

        Suppresses log output from the fake dht if used version of dhtproto
        supports it.

    ***************************************************************************/

    override public void ignoreErrors ( )
    {
        static if (is(typeof(this.node.ignoreErrors())))
            this.node.ignoreErrors();
    }
}

version (UnitTest)
{
    void initDht ( )
    {
        global_storage.clear();
        Dht.initialize();
    }
}

/*******************************************************************************

    Basic put()/get() test

*******************************************************************************/

unittest
{
    initDht();
    dht.put("unittest_channel", 123, "abcd"[]);
    auto s = dht.get!(mstring)("unittest_channel", 123);
    test!("==")(s, "abcd");
}

/*******************************************************************************

    Serializing put()/get() test

*******************************************************************************/

unittest
{
    struct Something
    {
        int a, b;
    }

    initDht();
    dht.put("unittest_channel", 123, Something(42, 43));
    auto s = dht.get!(Something)("unittest_channel", 123);
    test!("==")(s, Something(42, 43));
}

/*******************************************************************************

    Basic getAllKeys()/getAll() test

*******************************************************************************/

unittest
{
    initDht();

    istring[hash_t] data = [
        100 : "100"[],
        101 : "101",
        102 : "102"
    ];

    foreach (key, value; data)
        dht.put("unittest_channel", key, value);

    auto keys = dht.getAllKeys("unittest_channel");
    test!("==")(keys.length, data.length);
    foreach (key; keys)
        test!("in")(key, data);

    auto records = dht.getAll!(mstring)("unittest_channel");
    test!("==")(records.length, data.length);

    foreach (record; records)
        test!("==")(record.value, data[record.key]);
}

/*******************************************************************************

    Serializing getAllKeys()/getAll() test

*******************************************************************************/

unittest
{
    initDht();

    struct Something
    {
        int a, b;
    }

    Something[hash_t] data = [
        200 : Something(1, 2),
        210 : Something(7, 8),
        220 : Something(9, 10)
    ];

    foreach (key, value; data)
        dht.put("unittest_channel", key, value);

    auto keys = dht.getAllKeys("unittest_channel");
    test!("==")(keys.length, data.length);
    foreach (key; keys)
        test!("in")(key, data);

    auto records = dht.getAll!(Something)("unittest_channel");
    test!("==")(records.length, data.length);

    foreach (record; records)
        test!("==")(record.value, data[record.key]);
}

/*******************************************************************************

    Serializing, versioned put()/get() test

*******************************************************************************/

unittest
{
    struct Something
    {
        const StructVersion = 1;
        int a, b;
    }

    initDht();
    dht.put("unittest_channel", 123, Something(42, 43));
    auto s = dht.get!(Something)("unittest_channel", 123);
    test!("==")(s, Something(42, 43));
}

/*******************************************************************************

    getSize() tests

*******************************************************************************/

unittest
{
    // Ensure the storage is empty
    global_storage.clear();

    // Empty channel
    {
        initDht();
        auto size = dht.getSize("non_existent_channel");
        test!("==")(size.records, 0);
        test!("==")(size.bytes, 0);
    }

    // Channel with one record
    {
        initDht();
        dht.put("unittest_channel", 123, "abcd"[]);
        auto size = dht.getSize("unittest_channel");
        test!("==")(size.records, 1);
        test!("==")(size.bytes, 4);
    }
}
