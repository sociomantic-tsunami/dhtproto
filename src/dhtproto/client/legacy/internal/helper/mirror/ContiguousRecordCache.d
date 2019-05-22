/*******************************************************************************

    Simple cache of contiguous (deserialized) struct records

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.helper.mirror.ContiguousRecordCache;


/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.client.legacy.internal.helper.mirror.model.IContiguousRecordCache;

import ocean.transition;
import ocean.core.Verify;
import ocean.util.container.map.model.IAllocator;
import ocean.util.container.map.Map : StandardKeyHashingMap;
import ocean.util.serialize.contiguous.Contiguous;
import ocean.util.serialize.contiguous.Util : copy;

version (UnitTest)
{
    import ocean.core.Test;
}


/*******************************************************************************

    Simple cache of contiguous struct records

    Template params:
        S = struct to be stored in the cache
        Key = type of key used by the cache

*******************************************************************************/

public class ContiguousRecordCache ( S, Key = hash_t )
    : StandardKeyHashingMap!(Contiguous!(S), Key),
      IContiguousRecordCache!(S, Key)
{
    /***************************************************************************

        Constructor

        Params:
            n = expected number of elements in cache
            load_factor = ratio of n to the number of internal buckets

        Note:
            For data safety, the cached data is deep-copied into record,
            not merely assigned to it.

    ***************************************************************************/

    public this ( size_t n, float load_factor = 0.75 )
    {
        super(n, load_factor);
    }


    /***************************************************************************

        Constructor

        Params:
            allocator = custom bucket elements allocator
            n = expected number of elements in cache
            load_factor = ratio of n to the number of internal buckets

        Note:
            For data safety, the cached data is deep-copied into record,
            not merely assigned to it.

    ***************************************************************************/

    public this ( IAllocator allocator, size_t n, float load_factor = 0.75 )
    {
        super(allocator, n, load_factor);
    }


    /***************************************************************************

        Read an entry from the cache and copy its data into the provided
        contiguous record buffer

        Params:
            key = key of the record to read from the cache
            record = contiguous buffer into which to copy the cached
                     record; if no record exists in cache, record.ptr
                     should be null on function exit

        Note:
            For data safety, the cached data is deep-copied into record,
            not merely assigned to it.

    ***************************************************************************/

    override public void read ( Key key, ref Contiguous!(S) record )
    {
        if (auto rec = key in this)
        {
            copy(*rec, record);
            verify((rec.ptr is null) == (record.ptr is null));
        }
        else
        {
            record.reset;
        }
    }


    /***************************************************************************

        Write a copy of a record to the cache

        Params:
            key = key of the record
            record = record to write to the cache

        Note:
            For data safety, record data is deep-copied into the cache entry,
            not merely assigned to it.

    ***************************************************************************/

    override public void write ( Key key, Contiguous!(S) record )
    {
        auto entry = this.put(key);
        copy(record, *entry);
        verify((record.ptr is null) == (entry.ptr is null));
    }
}

unittest
{
    static struct S
    {
        int x;
        double y;
        mstring s;

        equals_t opEquals ( S rhs )
        {
            return (&this).x == rhs.x && (&this).y == rhs.y && (&this).s == rhs.s;
        }
    }

    auto cache = new ContiguousRecordCache!(S)(100);

    // test writing a struct copy to cache
    S input = { x: 23, y: 52.5, s: "hi".dup };
    Contiguous!(S) contiguous_input;
    copy(input, contiguous_input);
    test!("!is")(contiguous_input.ptr, null);

    cache.write(23, contiguous_input);
    test!("in")(23, cache);
    test!("!is")((23 in cache).ptr, null);
    test!("==")((23 in cache).ptr.x, 23);
    test!("==")((23 in cache).ptr.y, 52.5);
    test!("==")(*((23 in cache).ptr), input);

    /* test that altering input data after write
     * does not affect contents of cache
     */
    contiguous_input.ptr.x = 91;
    contiguous_input.ptr.y = 21.5;

    test!("in")(23, cache);
    test!("!is")((23 in cache).ptr, null);
    test!("==")((23 in cache).ptr.x, 23);
    test!("==")((23 in cache).ptr.y, 52.5);
    test!("==")(*((23 in cache).ptr), input);
    test!("!=")(*((23 in cache).ptr), *(contiguous_input.ptr));

    // test reading a struct copy from cache
    Contiguous!(S) contiguous_output;
    test!("is")(contiguous_output.ptr, null);
    cache.read(23, contiguous_output);
    test!("!is")(contiguous_output.ptr, null);
    test!("==")(contiguous_output.ptr.x, 23);
    test!("==")(contiguous_output.ptr.y, 52.5);
    test!("==")(*((23 in cache).ptr), input);

    /* test that overwriting cache entry does
     * not affect previously-read data
     */
    cache.write(23, contiguous_input);
    test!("in")(23, cache);
    test!("!is")((23 in cache).ptr, null);
    test!("==")((23 in cache).ptr.x, 91);
    test!("==")((23 in cache).ptr.y, 21.5);
    test!("==")(*((23 in cache).ptr), *(contiguous_input.ptr));
    test!("!=")(*((23 in cache).ptr), input);

    test!("!is")(contiguous_output.ptr, null);
    test!("==")(contiguous_output.ptr.x, 23);
    test!("==")(contiguous_output.ptr.y, 52.5);
    test!("==")(*(contiguous_output.ptr), input);

    IContiguousRecordCache!(S) icache = new ContiguousRecordCache!(S)(100);
}
