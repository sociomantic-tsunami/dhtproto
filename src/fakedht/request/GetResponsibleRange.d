/*******************************************************************************

    Turtle implementation of DHT `GetResponsibleRange` request

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

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

public scope class GetResponsibleRange : Protocol.GetResponsibleRange
{
    import fakedht.mixins.RequestConstruction;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();

    /***************************************************************************

        Must return minimum and maximum allowed hash value this node
        is responsible for.

        Params:
            min = minimal allowed hash
            max = maximal allowed hash

    ***************************************************************************/

    override protected void getRangeLimits ( out hash_t min, out hash_t max )
    {
        min = hash_t.min;
        max = hash_t.max;
    }
}
