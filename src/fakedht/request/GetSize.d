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

        Gets the aggregated size of all channels.

        Params:
            value_getter_dg = The delegate that is called with the metadata
                              that includes the size.

    ***************************************************************************/

    override protected void getSizeData (
        scope void delegate ( SizeData ) value_getter_dg )
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

        value_getter_dg(result);
    }
}
