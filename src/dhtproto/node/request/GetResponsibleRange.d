/*******************************************************************************

    Protocol base for DHT `GetResponsibleRange` request

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.GetResponsibleRange;

/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.node.request.model.DhtCommand;

/*******************************************************************************

    Request protocol

*******************************************************************************/

public abstract scope class GetResponsibleRange : DhtCommand
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
        super(DhtConst.Command.E.GetResponsibleRange, reader, writer, resources);
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
        hash_t min, max;
        this.getRangeLimits(min, max);
        this.writer.write(min);
        this.writer.write(max);
    }

    /***************************************************************************

        Must return minimum and maximum allowed hash value this node
        is responsible for.

        Params:
            min = minimal allowed hash
            max = maximal allowed hash

    ***************************************************************************/

    abstract protected void getRangeLimits ( out hash_t min, out hash_t max );
}
