/*******************************************************************************

    Protocol base for DHT `GetChannels` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.GetChannels;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhtproto.node.request.model.DhtCommand;

/*******************************************************************************

    GetChannels request protocol

*******************************************************************************/

public abstract scope class GetChannels : DhtCommand
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
        super(DhtConst.Command.E.GetChannels, reader, writer, resources);
    }

    /***************************************************************************

        No data expected for GetChannels request

    ***************************************************************************/

    final override protected void readRequestData ( ) { }

    /***************************************************************************

        Write status and response data

    ***************************************************************************/

    final override protected void handleRequest ( )
    {
        this.writer.write(DhtConst.Status.E.Ok);
        this.getChannelsIds(
            ( const(void)[] id )
            {
                this.writer.writeArray(id);
            });
        this.writer.writeArray(""); // End of list
    }

    /***************************************************************************

        Must return list of all channels stored in this node.

        Params:
            value_getter_dg = The delegate that is called with the list of
                              channel names.

    ***************************************************************************/

    abstract protected void getChannelsIds (
        scope void delegate ( const(void)[] ) value_getter_dg );
}
