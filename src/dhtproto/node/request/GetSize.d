/*******************************************************************************

    Protocol base for DHT `GetSize` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.GetSize;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.meta.types.Qualifiers;

import dhtproto.node.request.model.DhtCommand;

/*******************************************************************************

    GetChannels request protocol

*******************************************************************************/

public abstract class GetSize : DhtCommand
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
        super(DhtConst.Command.E.GetSize, reader, writer, resources);
    }

    /***************************************************************************

        Payload structs that holds requested metadata

    ***************************************************************************/

    protected struct SizeData
    {
        mstring address;
        ushort port;
        ulong  records;
        ulong  bytes;
    }

    /***************************************************************************

        No data expected for GetSize request

    ***************************************************************************/

    final override protected void readRequestData ( ) { }

    /***************************************************************************

        Write status and response data

    ***************************************************************************/

    final override protected void handleRequest ( )
    {
        this.getSizeData(
            ( SizeData data )
            {
                this.writer.write(DhtConst.Status.E.Ok);

                // TODO: is there a need to send the addr/port?
                // surely the client knows this anyway?
                this.writer.writeArray(data.address);
                this.writer.write(data.port);
                this.writer.write(data.records);
                this.writer.write(data.bytes);
            });
    }

    /***************************************************************************

        Gets the aggregated size of all channels.

        Params:
            value_getter_dg = The delegate that is called with the metadata
                              that includes the size.

    ***************************************************************************/

    abstract protected void getSizeData (
        scope void delegate ( SizeData ) value_getter_dg );
}
