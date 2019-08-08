/*******************************************************************************

    Protocol base for DHT `Remove` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.Remove;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhtproto.node.request.model.SingleKey;

/*******************************************************************************

    Request protocol

*******************************************************************************/

public abstract scope class Remove : SingleKey
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
        super(DhtConst.Command.E.Remove, reader, writer, resources);
    }

    /***************************************************************************

        Params:
            channel_name = channel name for request that was read and validated
                earlier
            key = any string that can act as DHT key

    ***************************************************************************/

    final override protected void handleSingleKeyRequest( cstring channel_name,
        cstring key )
    {
        this.writer.write(DhtConst.Status.E.Ok);
        this.remove(channel_name, key);
    }

    /***************************************************************************

        Removes the record from the channel

        Params:
            channel_name = name of channel to remove from
            key = key of record to remove

    ***************************************************************************/

    abstract protected void remove ( cstring channel_name, cstring key );
}
