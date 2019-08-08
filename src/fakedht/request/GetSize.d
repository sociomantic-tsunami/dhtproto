/*******************************************************************************

    Turtle implementation of DHT `GetSize` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.GetSize;

/*******************************************************************************

    Imports

*******************************************************************************/

import Protocol = dhtproto.node.request.GetSize;

/*******************************************************************************

    GetChannels request protocol

*******************************************************************************/

public scope class GetSize : Protocol.GetSize
{
    import fakedht.mixins.RequestConstruction;
    import fakedht.Storage;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();

    /***************************************************************************

        Must return aggregated size of all channels.

        Returns:
            metadata that includes the size

    ***************************************************************************/

    override protected SizeData getSizeData ( )
    {
        SizeData result;
        auto channels = global_storage.getChannelList();

        foreach (channel; channels)
        {
            size_t records, bytes;
            global_storage.getVerify(channel).countSize(records, bytes);
            result.records += records;
            result.bytes += bytes;
        }

        return result;
    }
}
