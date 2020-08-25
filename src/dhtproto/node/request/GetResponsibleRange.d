/*******************************************************************************

    Protocol base for DHT `GetResponsibleRange` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

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

public abstract class GetResponsibleRange : DhtCommand
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
        this.getRangeLimits(
            ( hash_t min, hash_t max )
            {
                this.writer.write(DhtConst.Status.E.Ok);
                this.writer.write(min);
                this.writer.write(max);
            });
    }

    /***************************************************************************

        Get the minimum and maximum allowed hash value this node
        is responsible for.

        Params:
            value_getter_dg = The delegate that is called with the minimum and
                              the maximum allowed hashes.

    ***************************************************************************/

    abstract protected void getRangeLimits (
        scope void delegate ( hash_t min, hash_t max ) value_getter_dg );
}
