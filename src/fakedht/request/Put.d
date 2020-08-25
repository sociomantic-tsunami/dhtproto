/*******************************************************************************

    Turtle implementation of DHT `Put` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.Put;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.meta.types.Qualifiers;

import Protocol = dhtproto.node.request.Put;

/*******************************************************************************

    Request implementation

*******************************************************************************/

public class Put : Protocol.Put
{
    import fakedht.mixins.RequestConstruction;
    import fakedht.Storage;
    import swarm.util.RecordBatcher;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();

    /***************************************************************************

        Verifies that this node is allowed to handle records with given hash

        Params:
            key = hash to check

        Returns:
            'true' if fits in allowed range

    ***************************************************************************/

    override protected bool isAllowed ( cstring key )
    {
        return true;
    }

    /***************************************************************************

        Verifies that this node is allowed to store records of given size

        Params:
            size = size to check

        Returns:
            'true' if size is allowed

    ***************************************************************************/

    override protected bool isSizeAllowed ( size_t size )
    {
        return true;
    }

    /***************************************************************************

        Tries storing record in DHT and reports success status

        Params:
            channel = channel to write record to
            key = record key
            value = record value

        Returns:
            'true' if storing was successful

    ***************************************************************************/

    override protected bool putRecord ( cstring channel, cstring key,
        in void[] value )
    {
        global_storage.getCreate(channel).put(key, value);
        return true;
    }

    /***************************************************************************

        Returns:
            the maximum size (in bytes) allowed for a record to be added to the
            storage engine

    ***************************************************************************/

    override protected size_t recordSizeLimit ( )
    {
        return 128 * 1024;
    }
}
