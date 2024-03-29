/*******************************************************************************

    Protocol base for DHT `GetNumConnections` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.GetNumConnections;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.meta.types.Qualifiers;

import dhtproto.node.request.model.DhtCommand;

/*******************************************************************************

    Request protocol

*******************************************************************************/

public abstract class GetNumConnections : DhtCommand
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
        super(DhtConst.Command.E.GetNumConnections, reader, writer, resources);
    }

    /***************************************************************************

        Payload struct that holds the data requested

    ***************************************************************************/

    protected struct NumConnectionsData
    {
        mstring address;
        ushort  port;
        ulong   num_conns;
    }

    /***************************************************************************

        No data expected for GetNumConnections request

    ***************************************************************************/

    final override protected void readRequestData ( ) { }

    /***************************************************************************

        Write status and response data

    ***************************************************************************/

    final override protected void handleRequest ( )
    {
        this.getConnectionsData(
            ( NumConnectionsData data )
            {
                this.writer.write(DhtConst.Status.E.Ok);

                // TODO: is there a need to send the addr/port?
                // surely the client knows this anyway?
                this.writer.writeArray(data.address);
                this.writer.write(data.port);
                this.writer.write(data.num_conns);
            }
        );
    }

    /***************************************************************************

        Gets the total num_conns of established connections to this node.

        Params:
            value_getter_dg = The delegate that is called with the metadata
                              that includes number of established connections.

    ***************************************************************************/

    abstract protected void getConnectionsData (
        scope void delegate ( NumConnectionsData ) value_getter_dg );
}
