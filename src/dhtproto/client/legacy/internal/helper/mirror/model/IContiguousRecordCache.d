/*******************************************************************************

    Interface for cache of contiguous (deserialized) struct records

    Copyright:
        Copyright (c) 2016-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.helper.mirror.model.IContiguousRecordCache;


/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;
import ocean.util.serialize.contiguous.Contiguous;


/*******************************************************************************

    Interface for cache of contiguous struct records

    Template params:
        S = struct type to store in cache

*******************************************************************************/

public interface IContiguousRecordCache ( S, Key = hash_t )
{
    /***************************************************************************

        Read an entry from the cache and copy its data into the provided
        contiguous record buffer

        Params:
            key = key of the record to read from the cache
            record = contiguous buffer into which to copy the cached
                     record; if no record exists in cache, record.ptr
                     should be null on function exit

        Note:
            For data safety, implementations should ensure the cached data
            is deep-copied into `record`, not merely assigned to it.

    ***************************************************************************/

    void read ( Key key, ref Contiguous!(S) record );


    /***************************************************************************

        Write a copy of a record to the cache

        Params:
            key = key with which to associate the record
            record = contiguous record to write to the cache

        Note:
            For data safety, implementations should ensure that record data
            is deep-copied into the cache entry, not merely assigned to it.

    ***************************************************************************/

    void write ( Key key, Contiguous!(S) record );
}
