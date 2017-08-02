/*******************************************************************************

    Turtle implementation of DHT `Remove` request

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.Remove;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import Protocol = dhtproto.node.request.Remove;

/*******************************************************************************

    Request implementation

*******************************************************************************/

public class Remove : Protocol.Remove
{
    import fakedht.mixins.RequestConstruction;
    import fakedht.Storage;

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

        Removes the record from the channel

        Params:
            channel_name = name of channel to remove from
            key = key of record to remove

    ***************************************************************************/

    override protected void remove ( cstring channel_name, cstring key )
    {
        auto channel = global_storage.get(channel_name);
        if (channel !is null)
            channel.remove(key);
    }
}
