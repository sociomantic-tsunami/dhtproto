/*******************************************************************************

    Protocol base for DHT `Exists` request

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.Exists;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhtproto.node.request.model.SingleKey;

/*******************************************************************************

    Request protocol

*******************************************************************************/

public abstract scope class Exists : SingleKey
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
        super(DhtConst.Command.E.Exists, reader, writer, resources);
    }

    /***************************************************************************
    
        Params:
            channel_name = channel name for request that was read and validated
                earlier
            key = any string that can act as DHT key

    ***************************************************************************/

    final override protected void handleSingleKeyRequest ( cstring channel_name,
        cstring key  )
    {
        this.writer.write(DhtConst.Status.E.Ok);
        this.writer.write(this.recordExists(channel_name, key));
    }

    /***************************************************************************

        Force "accept-all" behaviour for `isAllowed`
        
        Hash range check isn't done for read requests (including 'Exists').
        It's a practical concern to keep the dht running as best as possible,
        while a redistribution is in progress.
        
        The situation is as follows:
        1. all writing clients are shut down. Readers stay active.
        2. a redistribution is triggered
        3. the nodes immediately change their hash range. Data transfer takes
           some time.
        4. reading clients are querying the original nodes. Decision is to still
           return these records, until they're transferred to the new nodes,
           even though they're "officially" not within the hash range of the
           node being queried.

        Params:
            key = key to check

        Returns:
            'true'

    ***************************************************************************/

    final override protected bool isAllowed ( cstring key )
    {
        return true;
    }

    /***************************************************************************

        Must check if there is any record in specified channel with specified
        key

        Params:
            channel_name = name of channel to check
            key = key of record to check

        Returns:
            'true' if such record exists

    ***************************************************************************/

    abstract protected bool recordExists ( cstring channel_name, cstring key );
}
