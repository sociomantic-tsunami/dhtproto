/*******************************************************************************

    Struct used to deserialize a list of node address / hash range tuples while
    handling Redistribute requests.

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.params.RedistributeNode;

/*******************************************************************************

    Imports

*******************************************************************************/

public struct RedistributeNode
{
    import swarm.Const : NodeItem;
    import swarm.util.Hash : HashRange;

    /***************************************************************************

        IP address / port of node

    ***************************************************************************/

    public NodeItem node;

    /***************************************************************************

        Hash responsibility range of node

    ***************************************************************************/

    public HashRange range;
}
