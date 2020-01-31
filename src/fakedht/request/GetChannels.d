/*******************************************************************************

    Turtle implementation of DHT `GetChannels` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.GetChannels;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.meta.types.Qualifiers;

import Protocol = dhtproto.node.request.GetChannels;

/*******************************************************************************

    GetChannels request implementation

*******************************************************************************/

public scope class GetChannels : Protocol.GetChannels
{
    import fakedht.mixins.RequestConstruction;
    import fakedht.Storage;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();

    /***************************************************************************

        Must return list of all channels stored in this node.

        Params:
            value_getter_dg = The delegate that is called with the list of
                              channel names.

    ***************************************************************************/

    override protected void getChannelsIds (
        scope void delegate ( const(void)[] ) value_getter_dg )
    {
        foreach (ref id; global_storage.getChannelList())
        {
            value_getter_dg(id);
        }
    }
}
