/*******************************************************************************

    Helper struct that wraps a key and value with functions to generate records

    Records can be generated either sequentially or non-sequentially. Both
    functions are deterministic.

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.util.Record;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.meta.types.Qualifiers;

/*******************************************************************************

    Helper struct

*******************************************************************************/

public struct Record
{
    import ocean.io.digest.Fnv1;
    import ocean.text.convert.Formatter;

    /***************************************************************************

        Record key

    ***************************************************************************/

    hash_t key;

    /***************************************************************************

        Record value

    ***************************************************************************/

    mstring val;

    /***************************************************************************

        Generates a record from the given index, i. The key of the produced
        record will be equal to i. Thus, if this function is called multiple
        times with incrementing i, the keys of generated records will form a
        sequential series.

        Params:
            i = index of record

        Returns:
            record generated from i

    ***************************************************************************/

    static public Record sequential ( uint i )
    {
        return Record.fromHash(cast(hash_t)i);
    }

    /***************************************************************************

        Generates a record from the given index, i. The key of the produced
        record will be equal to the hash of i. Thus, if this function is called
        multiple times with incrementing i, the keys of generated records will
        be essentially randomly ordered (i.e. spread or non-sequential).
        Because of the method used to generate the key (a hash function),
        however, the function is deterministic.

        Params:
            i = index of record

        Returns:
            record generated from i

    ***************************************************************************/

    static public Record spread ( uint i )
    {
        return Record.fromHash(Fnv1a(i));
    }

    /***************************************************************************

        Generates a record from the given key. The value is set to the string
        representation of the key.

        Params:
            key = key of record

        Returns:
            generated record

    ***************************************************************************/

    static private Record fromHash ( hash_t key )
    {
        Record r;
        r.key = key;
        sformat(r.val, "{}", r.key);
        return r;
    }
}

