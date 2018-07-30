/*******************************************************************************

    Protocol base for DHT `GetVersion` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.GetVersion;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhtproto.node.request.model.DhtCommand;

/*******************************************************************************

    Request protocol

*******************************************************************************/

public abstract scope class GetVersion : DhtCommand
{
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
        super(DhtConst.Command.E.GetVersion, reader, writer, resources);
    }

    /***************************************************************************

        No-op

    ***************************************************************************/

    final override protected void readRequestData ( ) { }

    /***************************************************************************

        Sends configured version number

    ***************************************************************************/

    final override protected void handleRequest ( )
    {
        this.writer.write(DhtConst.Status.E.Ok);
        this.writer.writeArray(this.getVersion());
    }

    /***************************************************************************

        Must return API version number

    ***************************************************************************/

    final protected cstring getVersion ( )
    {
        return DhtConst.ApiVersion;
    }
}
