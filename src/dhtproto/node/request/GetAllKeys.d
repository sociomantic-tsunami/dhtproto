/*******************************************************************************

    Protocol base for DHT `GetAllKeys` request

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.GetAllKeys;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhtproto.node.request.model.CompressedBatch;

/*******************************************************************************

    GetAllKeys request protocol

*******************************************************************************/

public abstract scope class GetAllKeys : CompressedBatch!(mstring)
{
    import dhtproto.node.request.model.DhtCommand;

    import dhtproto.client.legacy.DhtConst;

    /***************************************************************************

        Constructor

        Params:
            reader = FiberSelectReader instance to use for read requests
            writer = FiberSelectWriter instance to use for write requests
            resources = object providing resource getters

    ***************************************************************************/

    public this ( FiberSelectReader reader, FiberSelectWriter writer,
        DhtCommand.Resources resources )
    {
        super(DhtConst.Command.E.GetAllKeys, reader, writer, resources);
    }
}
