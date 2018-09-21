/*******************************************************************************

    Fake DHT node Get request implementation.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.neo.request.Get;

/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.node.neo.request.Get;

import fakedht.neo.SharedResources;
import swarm.neo.node.RequestOnConn;
import swarm.neo.request.Command;

import ocean.transition;

/*******************************************************************************

    Fake node implementation of the v0 Get request protocol.

*******************************************************************************/

public class GetImpl_v0 : GetProtocol_v0
{
    import fakedht.Storage;
    import ocean.core.Array : copy;

    /***************************************************************************

        Checks whether the node is responsible for the specified key.

        Params:
            key = key of record to write

        Returns:
            true if the node is responsible for the key

    ***************************************************************************/

    override protected bool responsibleForKey ( hash_t key )
    {
        // In the fake DHT, we always have a single node responsible for all
        // keys.
        return true;
    }

    /***************************************************************************

        Gets a single record from the storage engine.

        Params:
            channel = channel to read from
            key = key of record to read
            dg = called with the value of the record, if it exists

        Returns:
            true if the operation succeeded (the record was fetched or did not
            exist); false if an error occurred

    ***************************************************************************/

    override protected bool get ( cstring channel, hash_t key,
        scope void delegate ( Const!(void)[] value ) dg )
    {
        auto value_in_channel = global_storage.getCreate(channel).get(key);
        if ( value_in_channel !is null )
            dg(value_in_channel);
        return true;
    }
}
