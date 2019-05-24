/*******************************************************************************

    Protocol base for DHT `GetChannelSize` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.GetChannelSize;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhtproto.node.request.model.SingleChannel;

/*******************************************************************************

    RemoveChannel request protocol

*******************************************************************************/

public abstract scope class GetChannelSize : SingleChannel
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
        super(DhtConst.Command.E.GetChannelSize, reader, writer, resources);
    }

    /***************************************************************************

        Payload struct that will hold requesed data

    ***************************************************************************/

    protected struct ChannelSizeData
    {
        mstring address;
        ushort port;
        ulong  records;
        ulong  bytes;
    }

    /***************************************************************************

        Replies with ChannelSizeData content as appropriate

        Params:
            channel_name = name of channel to be queried

    ***************************************************************************/

    final override protected void handleChannelRequest ( cstring channel_name )
    {
        this.writer.write(DhtConst.Status.E.Ok);

        this.getChannelData(channel_name,
            ( ChannelSizeData data )
            {
                // TODO: is there a need to send the addr/port?
                // surely the client knows this anyway?
                this.writer.writeArray(data.address);
                this.writer.write(data.port);
                this.writer.write(data.records);
                this.writer.write(data.bytes);
            });
    }

    /***************************************************************************

        Gets the size metadata for specified channel. Overriden in
        actual implementors of dhtnode protocol.

        Params:
            channel_name = name of channel to be queried
            value_getter_dg = The delegate that is called with the channel data.

    ***************************************************************************/

    abstract protected void getChannelData ( cstring channel_name,
        scope void delegate ( ChannelSizeData ) value_getter_dg );
}
