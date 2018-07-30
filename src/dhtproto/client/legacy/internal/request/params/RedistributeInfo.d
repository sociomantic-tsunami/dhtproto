/*******************************************************************************

    Struct containing the fields requires for the Redistribute request. These
    are wrapped in a struct in order for them to be conveniently returnable by
    the user's input delegate.

    Copyright:
        Copyright (c) 2014-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.request.params.RedistributeInfo;



/*******************************************************************************

    Imports

*******************************************************************************/

import swarm.Const : NodeItem;
import swarm.util.Hash : HashRange;

import dhtproto.client.legacy.DhtConst : NodeHashRange;



public struct RedistributeInfo
{
    /***************************************************************************

        The new hash range for the node receiving the Redistribute request.

    ***************************************************************************/

    public HashRange new_range;


    /***************************************************************************

        The list of node addresses/ports, along with their hash ranges, which
        the node receiving the Redistribute request should forward data to.

    ***************************************************************************/

    public NodeHashRange[] redist_nodes;
}
