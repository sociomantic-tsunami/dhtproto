/*******************************************************************************

    Stub for Redistribute request (not supported)

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.Redistribute;

/*******************************************************************************

    Imports

*******************************************************************************/

import Protocol = dhtproto.node.request.Redistribute;

/*******************************************************************************

    Request implementation

*******************************************************************************/

public scope class Redistribute : Protocol.Redistribute
{
    import dhtproto.node.request.params.RedistributeNode;
    import fakedht.mixins.RequestConstruction;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();

    /**************************************************************************/

    override protected void adjustHashRange ( hash_t min, hash_t max )
    {
        assert (false, "Not supported by fake DHT node");
    }

    /**************************************************************************/

    override protected void redistributeData ( RedistributeNode[] dataset )
    {
        assert (false, "Not supported by fake DHT node");
    }
}
