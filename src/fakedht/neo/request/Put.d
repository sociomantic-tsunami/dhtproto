/*******************************************************************************

    Fake DHT node Put request implementation.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.neo.request.Put;

/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.node.neo.request.Put;

import fakedht.neo.SharedResources;
import swarm.neo.node.RequestOnConn;
import swarm.neo.request.Command;

import ocean.transition;

/*******************************************************************************

    Fake node implementation of the v0 Put request protocol.

*******************************************************************************/

public class PutImpl_v0 : PutProtocol_v0
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

        Writes a single record to the storage engine.

        Params:
            channel = channel to write to
            key = key of record to write
            value = record value to write

        Returns:
            true if the record was written; false if an error occurred

    ***************************************************************************/

    override protected bool put ( cstring channel, hash_t key, in void[] value )
    {
        // We need to dup value, as it is a slice to the neo connection's read
        // buffer.
        global_storage.getCreate(channel).put(key, value.dup);
        return true;
    }
}
