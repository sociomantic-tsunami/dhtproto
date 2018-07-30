/*******************************************************************************

    Turtle implementation of DHT `GetChannelSize` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.GetChannelSize;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import Protocol = dhtproto.node.request.GetChannelSize;

/*******************************************************************************

    GetChannelSize request implementation

*******************************************************************************/

public scope class GetChannelSize : Protocol.GetChannelSize
{
    import fakedht.mixins.RequestConstruction;
    import fakedht.Storage;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();

    /***************************************************************************

        Gets the size metadata for specified channel. Overriden in
        actual implementors of dhtnode protocol.

        Params:
            channel_name = name of channel to be queried

    ***************************************************************************/

    override protected ChannelSizeData getChannelData ( cstring channel_name )
    {
        ChannelSizeData result;
        auto channel = global_storage.get(channel_name);
        if (channel !is null)
            channel.countSize(result.records, result.bytes);
        return result;
    }
}
