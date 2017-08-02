/*******************************************************************************

    Turtle implementation of DHT `GetAllKeys` request

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.GetAllKeys;

/*******************************************************************************

    Imports

*******************************************************************************/

import Protocol = dhtproto.node.request.GetAllKeys;

/*******************************************************************************

    Request implementation

*******************************************************************************/

public scope class GetAllKeys : Protocol.GetAllKeys
{
    import fakedht.mixins.RequestConstruction;
    import fakedht.mixins.ChannelIteration;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();

    /***************************************************************************

        Adds iteration resources and override `getNext` method

    ***************************************************************************/

    mixin ChannelIteration!(IterationKind.Key);
}
