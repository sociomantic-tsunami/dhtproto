/*******************************************************************************

    Turtle implementation of DHT `GetVersion` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.GetVersion;

/*******************************************************************************

    Imports

*******************************************************************************/

import Protocol = dhtproto.node.request.GetVersion;

/*******************************************************************************

    Request implementation. Completely provided by base in this case.

*******************************************************************************/

public class GetVersion : Protocol.GetVersion
{
    import fakedht.mixins.RequestConstruction;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();
}
