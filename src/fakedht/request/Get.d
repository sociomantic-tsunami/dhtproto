/*******************************************************************************

    Turtle implementation of DHT `Get` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.Get;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.meta.types.Qualifiers;

import Protocol = dhtproto.node.request.Get;

/*******************************************************************************

    Request implementation

*******************************************************************************/

public class Get : Protocol.Get
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
        key and returns it if possible

        Params:
            channel_name = name of channel to query
            key = key of record to find
            value_getter_dg = The delegate that is called with the value.

    ***************************************************************************/

    override protected void getValue ( cstring channel_name, cstring key,
        scope void delegate ( const(void)[] ) value_getter_dg )
    {
        auto channel = global_storage.get(channel_name);

        if (channel !is null)
        {
            value_getter_dg(channel.get(key));
        }
    }
}
