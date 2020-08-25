/*******************************************************************************

    Turtle implementation of DHT `GetResponsibleRange` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.GetResponsibleRange;

/*******************************************************************************

    Imports

*******************************************************************************/

import Protocol = dhtproto.node.request.GetResponsibleRange;

/*******************************************************************************

    Request implementation

*******************************************************************************/

public class GetResponsibleRange : Protocol.GetResponsibleRange
{
    import fakedht.mixins.RequestConstruction;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();

    /***************************************************************************

        Get the return minimum and maximum allowed hash value this node
        is responsible for.

        Params:
            min = minimal allowed hash
            max = maximal allowed hash

    ***************************************************************************/

    override protected void getRangeLimits (
        scope void delegate ( hash_t min, hash_t max ) value_getter_dg )
    {
        value_getter_dg(hash_t.min, hash_t.max);
    }
}
