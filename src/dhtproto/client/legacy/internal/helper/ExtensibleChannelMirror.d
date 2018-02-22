/*******************************************************************************

    DHT channel mirror helper with support for plugin extensions.

    This module contains the basic extensible channel mirror class plus two very
    commonly needed plugins:
        1. RawRecordDeserializer, to deserialize the raw record values received
           from the DHT into a specific struct type
        2. DeserializedRecordCache, to store the deserialized records

    The documented unittest for ExtensibleChannelMirror demonstrates both of
    these plugins.

    Copyright:
        Copyright (c) 2016-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.helper.ExtensibleChannelMirror;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhtproto.client.legacy.internal.helper.mirror.model.MirrorBase;
import dhtproto.client.DhtClient;

/*******************************************************************************

    Extensible channel mirror class template. Derives from the basic
    ChannelMirror class and adds the facility for one of more "plugins" to
    perform user-defined handling of the incoming records received by the
    mirror. The plugins can be any sequence of callable entities
    C1, C2, ... Cn, such that the return type of Ci is the input type of Ci+1.
    The first plugin, C1, will be passed the RawRecord struct (see below), which
    contains the raw record key and value received from the DHT.

    Some commonly useful plugins are defined later in this module, but any
    user-defined plugins which fulfil the above criterion may be used.

    Notes about plugins:
        1. Plugins which perform validation on records may throw. This causes
           the invocation of subsequent plugins to be aborted.
        2. As with all data passed to the user via callbacks from the DHT
           client, the record values passed to plugins are stored in buffers
           owned by the DHT client. If the user wishes to modify these values,
           they must be copied into new buffers.

    Usage example:
        See documented unittest below.

    Template_Params:
        Dht = type of dht client (must be derived from DhtClient and contain the
            RequestScheduler plugin)
        MirrorImpl = type of channel mirror implementation; must be derived from
            MirrorBase!(Dht)
        Plugins = variadic list of record-handling plugins to be called (*in the
            order specified*) when records are received by the mirror

*******************************************************************************/

public class ExtensibleMirror
    ( Dht : DhtClient, MirrorImpl : MirrorBase!(Dht), Plugins ... ) : MirrorImpl
{
    import ocean.core.Exception;
    import ocean.core.Traits : ctfe_i2a;

    import swarm.util.Hash : isHash, straightToHash;

    /***************************************************************************

        Template argument sanity check.

    ***************************************************************************/

    static assert(Plugins.length,
        "Why use ExtensibleChannelMirror with no plugins?");

    /***************************************************************************

        Exception type thrown when an invalid key is received from the DHT.

    ***************************************************************************/

    public static class InvalidKeyException : Exception
    {
        mixin ReusableExceptionImplementation!();

        public void enforce ( cstring key,
            istring file = __FILE__, long line = __LINE__ )
        {
            if ( !isHash(key) )
            {
                throw this.set("Invalid DHT record key: ").append(key);
            }
        }
    }

    /***************************************************************************

        Plugins, passed to ctor.

    ***************************************************************************/

    private Plugins plugin_instances;

    /***************************************************************************

        Type of plugin error notification delegate.

    ***************************************************************************/

    private alias void delegate ( cstring channel, cstring key, cstring val,
        Exception e ) PluginNotifier;

    /***************************************************************************

        Plugin error notification delegate.

    ***************************************************************************/

    private PluginNotifier plugin_notifier;

    /***************************************************************************

        Exception instance thrown when an invalid key is received from the DHT.

    ***************************************************************************/

    private InvalidKeyException invalid_key;

    /***************************************************************************

        Constructor.

        Params:
            dht = dht client used to access dht
            channel = name of dht channel to mirror
            update_time_s = seconds to wait between successful GetAlls
            retry_time_s = seconds to wait between failed requests
            request_notifier = callback called for each request notification
                (may be null)
            plugin_notifier = callback called when an exception is caught while
                invoking a plugin (may be null). In this case, subsequent
                plugins are not invoked
            plugin_instances = instance of each plugin

    ***************************************************************************/

    public this ( Dht dht, cstring channel,
        uint update_time_s, uint retry_time_s,
        Dht.RequestNotification.Callback request_notifier,
        PluginNotifier plugin_notifier,
        Plugins plugin_instances )
    {
        super(dht, channel, update_time_s, retry_time_s, request_notifier);

        this.plugin_notifier = plugin_notifier;
        this.plugin_instances = plugin_instances;
        this.invalid_key = new InvalidKeyException;
    }

    /***************************************************************************

        Receives a value from the DHT, sanity checks that the key is a valid
        hash, then passes the record on to the chain of plugins.

        Params:
            key = record key
            value = record value
            single_value = flag indicating whether the record was received from
                a Listen request (true) or a GetAll request (false)

    ***************************************************************************/

    override protected void receiveRecord ( in char[] key, in char[] value,
        bool single_value )
    {
        try
        {
            // Check key validity and convert string key to hash_t
            this.invalid_key.enforce(key);
            auto raw = RawRecord(straightToHash(key), cast(ubyte[])value);

            // Invoke plugin chain
            mixin(pluginInvocation());
        }
        catch ( Exception e )
        {
            // Call the user's plugin error notifier (if provided) and skip
            // invocation of subsequent plugins for this record.
            if ( this.plugin_notifier )
            {
                this.plugin_notifier(this.channel_, key, value, e);
            }
        }
    }

    /***************************************************************************

        Generates a string containing code which calls all plugins in sequence,
        passing the output of one as the input of the next. The first plugin
        receives the raw record received from the DHT. (The symbol `raw` is
        expected to exist at the site where the code generated by this function
        is mixed in.)

        Returns:
            code to invoke the chain of plugins

    ***************************************************************************/

    private static mstring pluginInvocation ( )
    {
        mstring code;

        for ( size_t i = 0; i < Plugins.length; i++ )
        {
            auto input = i == 0
                ? "raw" // feed the initial, raw record into the first plugin
                : "r" ~ ctfe_i2a(i - 1); // subsequently, use output of previous
            auto output = "r" ~ ctfe_i2a(i);
            auto plugin = "this.plugin_instances[" ~ ctfe_i2a(i) ~ "]";

            code ~= "auto " ~ output ~ " = " ~ plugin ~ "(" ~ input ~ ");";
        }

        return code;
    }
}

import dhtproto.client.legacy.internal.helper.ChannelMirror;

/*******************************************************************************

    Extensible channel mirror class template based on the ChannelMirror
    implementation.

    Params:
        Dht = type of dht client (must be derived from DhtClient and contain the
            RequestScheduler plugin)
        Plugins = variadic list of record-handling plugins to be called (*in the
            order specified*) when records are received by the mirror

*******************************************************************************/

public template ExtensibleChannelMirror ( Dht : DhtClient, Plugins ... )
{
    alias ExtensibleMirror!(Dht, ChannelMirror!(Dht), Plugins)
        ExtensibleChannelMirror;
}

version ( UnitTest )
{
    import ocean.io.Stdout;
    import ocean.io.select.EpollSelectDispatcher;
    import ocean.util.serialize.contiguous.Serializer;
}

/// ExtensibleChannelMirror usage example
unittest
{
    void example ( )
    {
        // Channel to be mirrored
        istring channel = "channel";

        // Struct contained (serialized) in the channel
        static struct Record
        {
            import ocean.text.convert.Formatter;

            ulong update_time;
            hash_t id;
            size_t count;

            istring toString ( )
            {
                return format("[{}, {}, {}]",
                    this.update_time, this.id, this.count);
            }
        }

        // Connect to a DHT
        auto epoll = new EpollSelectDispatcher;
        auto dht = new SchedulingDhtClient(epoll);
        dht.addNode("127.0.0.1".dup, 6424);
        dht.nodeHandshake(
            (DhtClient.RequestContext, bool ok)
            {
                assert(ok);
            },
            null);
        epoll.eventLoop();

        // Add some records to the channel being mirrored
        const num_records = 10;
        for ( hash_t i = 0; i < num_records; i++ )
        {
            mstring put_dg ( DhtClient.RequestContext c )
            {
                Record r;
                r.update_time = c.integer;
                ubyte[] buf;
                return cast(mstring)Serializer.serialize(r, buf);
            }

            void notify_dg ( DhtClient.RequestNotification )
            {
            }

            dht.assign(dht.put(channel, i, &put_dg, &notify_dg).context(i));
        }
        epoll.eventLoop();

        // Create a mirror for the channel with the following plugins:
        //   1. a RecordDeserializer, to convert the raw record values into our
        //      struct type, Record.
        //   2. a RecordCache, to store the deserialized records.

        alias ExtensibleChannelMirror!(SchedulingDhtClient,
            RawRecordDeserializer!(Record), DeserializedRecordCache!(Record))
            ExampleMirror;

        auto deserializer = new RawRecordDeserializer!(Record);
        auto cache = new DeserializedRecordCache!(Record)(100);
        auto mirror = new ExampleMirror(dht, channel, 100, 2, null, null,
            deserializer, cache);

        // Fill the mirror, performing a one-shot GetAll request to fetch all
        // records in the channel and pass them through the plugin chain.
        mirror.fill();
        epoll.eventLoop();

        // Check the records in the cache.
        for ( hash_t i = 0; i < num_records; i++ )
        {
            DeserializedRecord!(Record).Record record;
            cache.cache.read(i, record);
            if ( record.ptr )
                Stdout.formatln("Cached record: key={}, update_time={}",
                    i, record.ptr.update_time);
        }
    }
}

// Test that a delegate can be passed as a plugin
unittest
{
    struct AStruct
    {
        int dg ( RawRecord r )
        {
            return 0;
        }
    }

    alias ExtensibleChannelMirror!(SchedulingDhtClient,
        int delegate ( RawRecord )) TestMirror;

    AStruct a_struct;
    auto dht = new SchedulingDhtClient(new EpollSelectDispatcher);
    auto mirror = new TestMirror(dht, "channel", 100, 2, null, null,
        &a_struct.dg);
}

// Test that a function can be passed as a plugin
unittest
{
    static int fn ( RawRecord r )
    {
        return 0;
    }

    alias ExtensibleChannelMirror!(SchedulingDhtClient,
        int function ( RawRecord )) TestMirror;

    auto dht = new SchedulingDhtClient(new EpollSelectDispatcher);
    auto mirror = new TestMirror(dht, "channel", 100, 2, null, null, &fn);
}

/*******************************************************************************

    Struct defining the basic record type received from the DHT: a hash key and
    a binary-chunk value. An instance of this struct is passed to the first
    plugin in the chain.

*******************************************************************************/

public struct RawRecord
{
    /***************************************************************************

        Record hash (converted from the hex-string key)

    ***************************************************************************/

    public hash_t key;

    /***************************************************************************

        Record value (raw binary data)

    ***************************************************************************/

    public void[] val;
}

/*******************************************************************************

    Struct template defining a record whose raw binary value has been
    deserialized to an instance of the struct T. Used by the RecordDeserializer
    plugin, below.

    Template_Params:
        T = type of struct to which record values are deserialized

*******************************************************************************/

public struct DeserializedRecord ( T )
{
    import ocean.util.serialize.contiguous.Contiguous;

    /***************************************************************************

        Type of deserialized records

    ***************************************************************************/

    public alias Contiguous!(T) Record;

    /***************************************************************************

        Record hash (converted from the hex-string key)

    ***************************************************************************/

    public hash_t key;

    /***************************************************************************

        Deserialized record value

    ***************************************************************************/

    public Record val;
}

/*******************************************************************************

    Record deserializer plugin which accepts a raw record from the DHT and
    converts the value by deserializing it to an instance of the struct T,
    outputting DeserializedRecord!(T).

    Template_Params:
        T = type of struct to which record values are deserialized

*******************************************************************************/

/* FIXME: These imports should be inside RawRecordDeserializer, but have to be
   placed here in order to avoid linker problems (most likely --deps problems
   caused by RawRecordDeserializer being a template).
*/
import ocean.util.serialize.Version : Version;
import ocean.util.serialize.contiguous.MultiVersionDecorator : VersionDecorator;

public class RawRecordDeserializer ( T )
{
    import ocean.util.serialize.contiguous.Contiguous;
    import ocean.util.serialize.contiguous.Deserializer;

    /***************************************************************************

        Alias for the deserialized DHT record

    ***************************************************************************/

    private alias Contiguous!(T) Record;

    /***************************************************************************

        Compile-time flag indicating if T is a versioned struct

    ***************************************************************************/

    private const bool isVersioned = Version.Info!(T).exists;

    static if (isVersioned)
    {
        /***********************************************************************

            Deserialization wrapper that handles struct version transitions

        ***********************************************************************/

        private VersionDecorator version_decorator;
    }

    /***************************************************************************

        Contiguous buffer into which to deserialize newly-received records

    ***************************************************************************/

    private Record new_dht_record_buffer;

    /***************************************************************************

        Constructor. Uses the standard record deserialization algorithm.

    ***************************************************************************/

    public this ( )
    {
        static if (isVersioned)
        {
            this.version_decorator = new VersionDecorator;
        }
    }

    /***************************************************************************

        Record handling method. Converts the value of the raw input record to an
        instance of struct T and returns DeserializedRecord!(T).

        Params:
            record = raw DHT record

        Returns:
            DeserializedRecord!(T), containing the deserialized record value (a
            slice to this.new_dht_record_buffer)

    ***************************************************************************/

    public DeserializedRecord!(T) opCall ( RawRecord record )
    {
        static if (isVersioned)
        {
            this.version_decorator.loadCopy(record.val, this.new_dht_record_buffer);
        }
        else
        {
            Deserializer.deserialize(record.val, this.new_dht_record_buffer);
        }

        return DeserializedRecord!(T)(record.key, this.new_dht_record_buffer);
    }
}

/*******************************************************************************

    Record cache plugin which stores deserialized records of value type T. The
    plugin does not alter the input record in any way and simply passes it out
    unaltered (enabling subsequent plugins to use it as well).

    Template_Params:
        T = type of record values to be stored in the cache

*******************************************************************************/

/* FIXME: These imports should be inside DeserializedRecordCache, but have to be
   placed here in order to avoid linker problems.
*/
import dhtproto.client.legacy.internal.helper.mirror.ContiguousRecordCache;

public class DeserializedRecordCache ( T )
{
    import ocean.util.serialize.contiguous.Contiguous;

    import dhtproto.client.legacy.internal.helper.mirror.model.IContiguousRecordCache;

    /***************************************************************************

        Alias for record cache interface

    ***************************************************************************/

    private alias IContiguousRecordCache!(T, hash_t) Cache;

    /***************************************************************************

        Alias for the type of read from/written to the cache

    ***************************************************************************/

    private alias Contiguous!(T) Record;

    /***************************************************************************

        Alias for default cache type

    ***************************************************************************/

    private alias ContiguousRecordCache!(T, hash_t) DefaultCache;

    /***************************************************************************

        Cache in which to store received DHT profile data

    ***************************************************************************/

    private Cache cache_;

    /***************************************************************************

        Constructor. Uses the standard cache.

        Params:
            n = expected number of records in the cache

    ***************************************************************************/

    public this ( size_t n )
    {
        this(new DefaultCache(n));
    }

    /***************************************************************************

        Constructor. Uses the specified cache.

        Params:
            cache = cache to use to store records

    ***************************************************************************/

    public this ( Cache cache )
    {
        assert(cache !is null);
        this.cache_ = cache;
    }

    /***************************************************************************

        Access the cache in which the mirror stores received records.

        Returns:
            the mirror's cache

    ***************************************************************************/

    public Cache cache ( )
    out ( c )
    {
        assert(c !is null);
    }
    body
    {
        return this.cache_;
    }

    /***************************************************************************

        Record handling method. Stores the received record in the cache.

        Params:
            record = deserialized DHT record

        Returns:
            passes on the input record, allowing chaining of further plugins

    ***************************************************************************/

    public DeserializedRecord!(T) opCall ( DeserializedRecord!(T) record )
    {
        this.cache_.write(record.key, record.val);
        return record;
    }
}
