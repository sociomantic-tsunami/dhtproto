/*******************************************************************************

    Fake DHT node Remove request implementation.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.neo.request.Remove;

import dhtproto.node.neo.request.Remove;

import fakedht.neo.SharedResources;
import swarm.neo.node.RequestOnConn;
import swarm.neo.request.Command;

import ocean.meta.types.Qualifiers;

/*******************************************************************************

    Fake node implementation of the v0 Remove request protocol.

*******************************************************************************/

public class RemoveImpl_v0 : RemoveProtocol_v0
{
    import fakedht.Storage;
    import dhtproto.common.RequestCodes : RequestCode;

    /// Request code / version. Required by ConnectionHandler.
    static immutable Command command = Command(RequestCode.Remove, 0);

    /// Request name for stats tracking. Required by ConnectionHandler.
    static immutable istring name = "Remove";

    /// Flag indicating whether timing stats should be gathered for requests of
    /// this type.
    static immutable bool timing = false;

    /// Flag indicating whether this request type is scheduled for removal. (If
    /// true, clients will be warned.)
    static immutable bool scheduled_for_removal = false;

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

        Removes a single record from the storage engine.

        Params:
            channel = channel to remove from
            key = key of record to remove
            existed = out value, set to true if the record was present and
                removed or false if the record was not present

        Returns:
            true if the operation succeeded (the record was removed or did not
            exist); false if an error occurred

    ***************************************************************************/

    override protected bool remove ( cstring channel, hash_t key,
        out bool existed )
    {
        existed = global_storage.getCreate(channel).remove(key);
        return true;
    }
}
