/*******************************************************************************

    Turtle implementation of DHT `Exists` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.Exists;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.meta.types.Qualifiers;

import Protocol = dhtproto.node.request.Exists;

/*******************************************************************************

    Request implementation

*******************************************************************************/

public class Exists : Protocol.Exists
{
    import fakedht.mixins.RequestConstruction;
    import fakedht.Storage;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();

    /***************************************************************************

        Checks if there is any record in specified channel with specified
        key

        Params:
            channel_name = name of channel to check
            key = key of record to check

        Returns:
            'true' if such record exists

    ***************************************************************************/

    override protected bool recordExists ( cstring channel_name, cstring key )
    {
        auto channel = global_storage.get(channel_name);
        if (channel is null)
            return false;
        return (channel.get(key) !is null);
    }
}
