/*******************************************************************************

    Protocol base for DHT `Get` request

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.Get;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhtproto.node.request.model.SingleKey;

/*******************************************************************************

    Request protocol

*******************************************************************************/

public abstract scope class Get : SingleKey
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
        super(DhtConst.Command.E.Get, reader, writer, resources);
    }

    /***************************************************************************

        Force "accept-all" behaviour for `isAllowed`
        
        Hash range check isn't done for read (Get) requests. It's a practical
        concern to keep the dht running as best as possible, while a
        redistribution is in progress.
        
        The situation is as follows:
        1. all writing clients are shut down. Readers stay active.
        2. a redistribution is triggered
        3. the nodes immediately change their hash range. Data transfer takes
           some time.
        4. reading clients are querying the original nodes. Decision is to still
           return these records, until they're transferred to the new nodes,
           even though they're "officially" not within the hash range of the
           node being queried.

    ***************************************************************************/

    final override protected bool isAllowed ( cstring key )
    {
        return true;
    }

    /***************************************************************************
    
        Sends queried record to client

        Params:
            channel_name = channel name for request that was read and validated
                earlier
            key = any string that can act as DHT key

    ***************************************************************************/

    final override protected void handleSingleKeyRequest ( cstring channel_name,
        cstring key )
    {
        this.writer.write(DhtConst.Status.E.Ok);
        this.writer.writeArray(this.getValue(channel_name, key));
    }

    /***************************************************************************

        Must check if there is any record in specified channel with specified
        key and return it if possible

        Params:
            channel_name = name of channel to query
            key = key of record to find

        Returns:
            value of queried record, empty array if not found

    ***************************************************************************/

    abstract protected Const!(void)[] getValue ( cstring channel_name, cstring key );
}
