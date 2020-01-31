/*******************************************************************************

    DHT channel serializer helper.

    Helper class template for dumping a cached or mirrored channel from a map
    (of some kind) in memory to disk, then loading it again at startup. The
    dumping can be done in either a blocking way (e.g. at application shutdown)
    or asynchronously via `fork` (e.g. periodically while the application is
    running).

    Notes:
        * In-memory data structure: Is assumed to be some kind of map, from
          `hash_t` keys to `Contiguous!(S)` values (where `S` is the type of
          the deserialized struct).
        * Blocking dump: Dumps the map without forking. If an asynchronous dump
          is already in progress, the call will block until the dump is
          finished, then start it again.
        * Asynchronous dump: When an asynchronous dump is in progress, further
          calls to `dump` will not start a second, clashing dump; the dump
          method will simply return.

    Copyright:
        Copyright (c) 2018 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.helper.ChannelSerializer;

import ocean.meta.types.Qualifiers;
import ocean.io.device.File;
import ocean.io.serialize.SimpleStreamSerializer;
import ocean.io.stream.Buffered;
import ocean.sys.SafeFork;
import ocean.util.container.map.Map;
import ocean.util.serialize.contiguous.Contiguous;
import ocean.util.serialize.contiguous.Deserializer;
import ocean.util.serialize.contiguous.MultiVersionDecorator;
import ocean.util.serialize.contiguous.Serializer;
import ocean.util.serialize.Version;

/*******************************************************************************

    DHT channel serializer helper.

    Params:
        S = type of record value stored in cached / mirrored channel

*******************************************************************************/

public class ChannelSerializer ( S )
{
    /// Path of the dump file.
    private istring path;

    /// Buffer for formatting temporary paths (see forkEntryPoint()).
    private mstring temp_path;

    /// Buffered output instance.
    private BufferedOutput buffered_output;

    /// Buffered input instance.
    private BufferedInput buffered_input;

    /// Fork helper for asynchronous dumping.
    private SafeFork fork;

    /// Delegate type required by `dump`.
    private alias void delegate ( void delegate ( hash_t, ref Contiguous!(S) ) )
        DumpRecordDg;

    /// Delegate type required by `load`.
    private alias void delegate ( hash_t, ref Contiguous!(S) ) LoadRecordDg;

    /// Delegate used by the fork for providing the records to be dumped. (Note
    /// that the fork copy-on-write behaviour means it's safe for this value to
    /// be changed while a fork is running.)
    private DumpRecordDg record_dump_dg;

    /// Buffer used for de/serialization of record values.
    private void[] serialize_buf;

    /// Version decorator, for record value structs that have version info.
    static if ( Version.Info!(S).exists )
        private VersionDecorator version_decorator;

    /***************************************************************************

        Constructor.

        Params:
            path = path of the dump file

    ***************************************************************************/

    public this ( istring path )
    {
        static immutable buffer_size = 64 * 1024;

        this.path = path;
        this.buffered_output = new BufferedOutput(null, buffer_size);
        this.buffered_input  = new BufferedInput(null, buffer_size);
        this.fork = new SafeFork(&this.forkEntryPoint);

        static if ( Version.Info!(S).exists )
            this.version_decorator = new VersionDecorator;
    }

    /***************************************************************************

        Dumps the provided associative array to disk.

        Params:
            aa = associative array to dump
            block = if true, performs a blocking dump; otherwise performs an
                asynchronous dump (see module header)

        Returns:
            true if a dump occurred; false if it was skipped

    ***************************************************************************/

    public bool dump ( Contiguous!(S)[hash_t] aa, bool block = false )
    {
        void dumpAA ( scope void delegate ( hash_t, ref Contiguous!(S) ) dump_record )
        {
            foreach ( k, v; aa)
                dump_record(k, v);
        }
        return this.dump(&dumpAA, block);
    }

    /***************************************************************************

        Dumps the provided map to disk.

        Params:
            map = map to dump
            block = if true, performs a blocking dump; otherwise performs an
                asynchronous dump (see module header)

        Returns:
            true if a dump occurred; false if it was skipped

    ***************************************************************************/

    public bool dump ( Map!(Contiguous!(S), hash_t) map, bool block = false )
    {
        void dumpMap ( scope void delegate ( hash_t, ref Contiguous!(S) ) dump_record )
        {
            foreach ( k, v; map)
                dump_record(k, v);
        }
        return this.dump(&dumpMap, block);
    }

    /***************************************************************************

        Dumps an arbitrary key-value data structure to disk.

        Params:
            record_dump_dg = delegate to receive a delegate to be called once
                per record to dump
            block = if true, performs a blocking dump; otherwise performs an
                asynchronous dump (see module header)

        Returns:
            true if a dump occurred; false if it was skipped

    ***************************************************************************/

    public bool dump ( scope DumpRecordDg record_dump_dg, bool block = false )
    {
        this.record_dump_dg = record_dump_dg;
        return this.fork.call(block);
    }

    /***************************************************************************

        Loads an associative array from disk.

        Params:
            aa = associative array to load into

    ***************************************************************************/

    public void load ( ref Contiguous!(S)[hash_t] aa )
    {
        void loadRecord ( hash_t k, ref Contiguous!(S) v )
        {
            aa[k] = v;
        }
        this.load(&loadRecord);
    }

    /***************************************************************************

        Loads a map from disk.

        Params:
            map = map to load into

    ***************************************************************************/

    public void load ( Map!(Contiguous!(S), hash_t) map )
    {
        void loadRecord ( hash_t k, ref Contiguous!(S) v )
        {
            (*map.put(k)) = v;
        }
        this.load(&loadRecord);
    }

    /***************************************************************************

        Loads an arbitrary key-value data structure from disk.

        Params:
            record_load_dg = delegate to be called once per loaded record

    ***************************************************************************/

    public void load ( scope LoadRecordDg record_load_dg )
    {
        size_t num_records;
        scope file = new File(this.path, File.ReadExisting);
        this.buffered_input.input(file);
        this.buffered_input.clear();
        SimpleStreamSerializer.read(this.buffered_input, num_records);

        for ( size_t i = 0; i < num_records; i++ )
        {
            hash_t k;
            Contiguous!(S) v;
            SimpleStreamSerializer.read(this.buffered_input, k);
            SimpleStreamSerializer.read(this.buffered_input, this.serialize_buf);

            static if ( Version.Info!(S).exists )
                v = this.version_decorator.loadCopy!(T)(this.serialize_buf, v);
            else
                Deserializer.deserialize(this.serialize_buf, v);

            record_load_dg(k, v);
        }
    }

    /***************************************************************************

        SafeFork entry point. Calls `this.new_record_dump_dg` to dump the
        provided data structure to disk.

    ***************************************************************************/

    private void forkEntryPoint ( )
    {
        size_t num_records;

        // Open file (with a temp name) and initialise buffer.
        scope file = new TempFile(this.path, this.temp_path);
        this.buffered_output.output(file);
        this.buffered_output.clear();

        // Once the file is written successfully, swap it to the real path.
        scope ( success )
        {
            this.buffered_output.flush();
            file.swap();
        }

        scope dumpRecord =
            ( hash_t k, ref Contiguous!(S) v )
            {
                // Serialize record.
                static if ( Version.Info!(S).exists )
                    VersionDecorator.store!(S)(*(v.ptr), this.serialize_buf);
                else
                    Serializer.serialize(*(v.ptr), this.serialize_buf);

                // Write record key and serialized value.
                SimpleStreamSerializer.write(this.buffered_output, k);
                SimpleStreamSerializer.write(this.buffered_output,
                    this.serialize_buf);

                num_records++;
            };

        // Write dummy file length.
        SimpleStreamSerializer.write(this.buffered_output, size_t.init);

        // Write all records sent by the dump delegate.
        this.record_dump_dg(dumpRecord);
        this.buffered_output.flush();

        // Write real file length.
        this.buffered_output.seek(0);
        SimpleStreamSerializer.write(this.buffered_output, num_records);
    }
}

version ( unittest )
{
    import ocean.util.container.map.HashMap;

    /// Record value struct used in all exampels and unittests.
    struct S
    {
        int i;
        bool b;
        cstring str;
    }
}

// Instantiate template to check compilation.
unittest
{
    ChannelSerializer!(S) ser;
}

/// Example of dumping a channel stored in the form of a HashMap of
/// Contiguous!(S) records.
unittest
{
    void dumpChannelFromMap ( HashMap!(Contiguous!(S)) map )
    {
        auto ser = new ChannelSerializer!(S)("test_channel");
        ser.dump(map, true);
    }
}

/// Example of loading a channel into a HashMap of Contiguous!(S) records.
unittest
{
    void loadChannelIntoMap ( HashMap!(Contiguous!(S)) map )
    {
        auto ser = new ChannelSerializer!(S)("test_channel");
        ser.load(map);
    }
}

/// Example of dumping a channel stored in an arbitrary container that can be
/// iterated over.
unittest
{
    void dumpChannelFromContainer ( )
    {
        void containerIterator (
            scope void delegate ( hash_t, ref Contiguous!(S) ) dump_record )
        {
            Contiguous!(S) v;

            // Iterate over your container and call `dump_record` once per
            // record. (In this example, we just iterate over an imaginary
            // container with a for loop.)
            for ( hash_t k = 0; k < 10; k++ )
                dump_record(k, v);
        }

        auto ser = new ChannelSerializer!(S)("test_channel");
        ser.dump(&containerIterator, true);
    }
}

/// Example of loading a channel into an arbitrary container.
unittest
{
    void loadChannelIntoContainer ( )
    {
        void containerInsert ( hash_t k, ref Contiguous!(S) v )
        {
            // Insert the provided record into your container.
        }

        auto ser = new ChannelSerializer!(S)("test_channel");
        ser.load(&containerInsert);
    }
}

/// System call. (Not defined in the runtime.)
extern ( C )
{
    int mkstemp(char *path_template);
}

/*******************************************************************************

    Helper class to write to a file in two steps:
        1. Opens a temp file to write to.
        2. Once file writing has finished (and succeeded), swap the path of the
           temp file to the final path.

*******************************************************************************/

private class TempFile : File
{
    import ocean.core.Array : concat;
    import core.stdc.stdio : rename;

    /// Final path of file.
    private cstring final_path;

    /// Pointer to buffer to format temp file name.
    private mstring* temp_path;

    /***************************************************************************

        Opens a temp file ready for writing.

        Params:
            path = final file path
            temp_path = pointer to buffer to format temp file name

    ***************************************************************************/

    public this ( cstring final_path, ref mstring temp_path )
    {
        this.final_path = final_path;
        this.temp_path = &temp_path;

        (*this.temp_path).concat(this.final_path, "XXXXXX", "\0");
        auto fd = mkstemp(this.temp_path.ptr);
        if ( fd == -1 )
            this.error(); // Throws an IOException

        // The oddly-named 'reopen' allows us to set the Device's fd.
        this.reopen(cast(Handle)fd);
    }

    /***************************************************************************

        Swaps the temp file to the final file path.

    ***************************************************************************/

    public void swap ( )
    {
        rename(this.temp_path.ptr, this.final_path.ptr);
    }
}
