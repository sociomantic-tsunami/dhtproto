/*******************************************************************************

    Turtle implementation of DHT `GetAll` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.GetAll;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.meta.types.Qualifiers;

import Protocol = dhtproto.node.request.GetAll;

/*******************************************************************************

    Request implementation

*******************************************************************************/

public class GetAll : Protocol.GetAll
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

    mixin ChannelIteration!(IterationKind.KeyValue);
}
