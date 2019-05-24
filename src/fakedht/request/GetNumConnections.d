/*******************************************************************************

    Turtle implementation of DHT `GetNumConnections` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.GetNumConnections;

/*******************************************************************************

    Imports

*******************************************************************************/

import Protocol = dhtproto.node.request.GetNumConnections;

/*******************************************************************************

    Request implementation

*******************************************************************************/

public scope class GetNumConnections : Protocol.GetNumConnections
{
    import ocean.core.Enforce;
    import fakedht.mixins.RequestConstruction;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();

    /***************************************************************************

        Gets the total num_conns of established connections to this node.

        Params:
            value_getter_dg = The delegate that is called with the metadata
                              that includes number of established connections.

    ***************************************************************************/

    override protected void getConnectionsData (
        scope void delegate ( NumConnectionsData ) /* value_getter_dg */ )
    {
        enforce(false,
            "GetNumConnections is not supported by the fake DHT node");
    }
}
