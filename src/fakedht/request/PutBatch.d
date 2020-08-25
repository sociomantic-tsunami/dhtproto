/*******************************************************************************

    Turtle implementation of DHT `PutBatch` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.PutBatch;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.meta.types.Qualifiers;

import Protocol = dhtproto.node.request.PutBatch;

/*******************************************************************************

    PutBatch request protocol

*******************************************************************************/

public class PutBatch : Protocol.PutBatch
{
    import fakedht.mixins.RequestConstruction;
    import fakedht.Storage;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();

    /***************************************************************************

        Verifies that this node is responsible of handling specified record key

        Params:
            key = key to check

        Returns:
            'true' if key is allowed / accepted

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
 }
