/*******************************************************************************

    Fake DHT node Exists request implementation.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.neo.request.Exists;

import dhtproto.node.neo.request.Exists;

import fakedht.neo.SharedResources;
import swarm.neo.node.RequestOnConn;
import swarm.neo.request.Command;

import ocean.transition;

/*******************************************************************************

    Fake node implementation of the v0 Exists request protocol.

*******************************************************************************/

public class ExistsImpl_v0 : ExistsProtocol_v0
{
    import fakedht.Storage;

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

        Checks whether a single record exists in the storage engine.

        Params:
            channel = channel to check in
            key = key of record to check
            found = out value, set to true if the record exists

        Returns:
            true if the operation succeeded; false if an error occurred

    ***************************************************************************/

    override protected bool exists ( cstring channel, hash_t key, out bool exists )
    {
        auto value_in_channel = global_storage.getCreate(channel).get(key);
        exists = value_in_channel !is null;
        return true;
    }
}
