/*******************************************************************************

    Fake DHT node Update request implementation.

    Copyright:
        Copyright (c) 2018 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.neo.request.Update;

import dhtproto.node.neo.request.Update;

import fakedht.neo.SharedResources;
import swarm.neo.node.RequestOnConn;
import swarm.neo.request.Command;

import ocean.meta.types.Qualifiers;

/*******************************************************************************

    Fake node implementation of the v0 Update request protocol.

*******************************************************************************/

public class UpdateImpl_v0 : UpdateProtocol_v0
{
    import fakedht.Storage;
    import dhtproto.common.RequestCodes : RequestCode;

    /// Request code / version. Required by ConnectionHandler.
    static immutable Command command = Command(RequestCode.Update, 0);

    /// Request name for stats tracking. Required by ConnectionHandler.
    static immutable istring name = "Update";

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

        Reads a single record from the storage engine.

        Params:
            channel = channel to read from
            key = key of record to read
            dg = called with the value of the record, if it exists

        Returns:
            true if the operation succeeded (the record was fetched or did not
            exist); false if an error occurred

    ***************************************************************************/

    override protected bool get ( cstring channel, hash_t key,
        scope void delegate ( const(void)[] value ) dg )
    {
        auto value_in_channel = global_storage.getCreate(channel).get(key);
        if ( value_in_channel !is null )
            dg(value_in_channel);
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

    /***************************************************************************

        Removes a single record from the storage engine.

        Params:
            channel = channel to remove to
            key = key of record to remove

        Returns:
            true if the record was removed; false if an error occurred

    ***************************************************************************/

    override protected bool remove ( cstring channel, hash_t key )
    {
        global_storage.getCreate(channel).remove(key);
        return true;
    }
}
