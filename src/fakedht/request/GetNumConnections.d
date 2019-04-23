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

        Must return total num_conns of established connections to this node.

        Returns:
            metadata that includes number of established connections

    ***************************************************************************/

    override protected NumConnectionsData getConnectionsData ( )
    {
        enforce(false,
            "GetNumConnections is not supported by the fake DHT node");
        return NumConnectionsData.init;
    }
}
