/*******************************************************************************

    Protocol base for DHT `RemoveChannel` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.RemoveChannel;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.meta.types.Qualifiers;

import dhtproto.node.request.model.SingleChannel;

/*******************************************************************************

    Request protocol

*******************************************************************************/

public abstract scope class RemoveChannel : SingleChannel
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
        super(DhtConst.Command.E.RemoveChannel, reader, writer, resources);
    }

    /***************************************************************************

        Make appropriate status response and forward to `removeChannel` to do
        actual work

        Params:
            channel_name = name of channel to be removed

    ***************************************************************************/

    override protected void handleChannelRequest ( cstring channel_name )
    {
        this.writer.write(DhtConst.Status.E.Ok);
        this.removeChannel(channel_name);
    }

    /***************************************************************************

        Must remove the specified channel from the storage engine.
        Any failure is considered critical.

        Params:
            channel_name = name of channel to be removed

    ***************************************************************************/

    abstract protected void removeChannel ( cstring channel_name );
}
