/*******************************************************************************

    Fake DHT node GetAll request implementation.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.neo.request.GetAll;

/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.node.neo.request.GetAll;

import fakedht.neo.SharedResources;
import swarm.neo.node.RequestOnConn;
import swarm.neo.request.Command;

import ocean.meta.types.Qualifiers;

/*******************************************************************************

    Fake node implementation of the v0 GetAll request protocol.

*******************************************************************************/

public class GetAllImpl_v0 : GetAllProtocol_v0
{
    import fakedht.Storage;
    import dhtproto.common.RequestCodes : RequestCode;
    import ocean.core.Verify;
    import ocean.text.convert.Hash : toHashT;

    /// Request code / version. Required by ConnectionHandler.
    static immutable Command command = Command(RequestCode.GetAll, 0);

    /// Request name for stats tracking. Required by ConnectionHandler.
    static immutable istring name = "GetAll";

    /// Flag indicating whether timing stats should be gathered for requests of
    /// this type.
    static immutable bool timing = false;

    /// Flag indicating whether this request type is scheduled for removal. (If
    /// true, clients will be warned.)
    static immutable bool scheduled_for_removal = false;

    /// Reference to channel being iterated over.
    private Channel channel;

    /// List of keys to visit during an iteration.
    private istring[] iterate_keys;

    /***************************************************************************

        Called to begin the iteration over the channel being fetched.

        Params:
            channel_name = name of channel to iterate over

        Returns:
            true if the iteration has been initialised, false to abort the
            request

    ***************************************************************************/

    override protected bool startIteration ( cstring channel_name )
    {
        this.channel = global_storage.getCreate(channel_name);
        this.iterate_keys = this.channel.getKeys();
        return true;
    }

    /***************************************************************************

        Called to continue the iteration over the channel being fetched,
        continuing from the specified hash (the last record received by the
        client).

        Params:
            channel_name = name of channel to iterate over
            continue_from = hash of last record received by the client. The
                iteration will continue from the next hash in the channel

        Returns:
            true if the iteration has been initialised, false to abort the
            request

    ***************************************************************************/

    override protected bool continueIteration ( cstring channel_name,
        hash_t continue_from )
    {
        this.channel = global_storage.getCreate(channel_name);
        this.iterate_keys = this.channel.getKeys();

        size_t index = this.iterate_keys.length;
        foreach_reverse ( i, str_key; this.iterate_keys )
        {
            hash_t key;
            auto ok = toHashT(str_key, key);
            verify(ok);
            if ( key == continue_from )
            {
                index = i;
                break;
            }
        }

        // Cut off any records after the last key iterated over.
        if ( index < this.iterate_keys.length )
            this.iterate_keys.length = index;

        return true;
    }

    /***************************************************************************

        Gets the next record in the iteration, if one exists.

        Params:
            dg = called with the key and value of the next record, if available

        Returns:
            true if a record was passed to `dg` or false if the iteration is
            finished

    ***************************************************************************/

    override protected bool getNext (
        scope void delegate ( hash_t key, const(void)[] value ) dg )
    {
        if ( this.iterate_keys.length == 0 )
            return false;

        auto str_key = this.iterate_keys[$-1];
        this.iterate_keys.length = this.iterate_keys.length - 1;

        hash_t key;
        auto ok = toHashT(str_key, key);
        verify(ok);
        auto value = this.channel.get(key);

        dg(key, value);
        return true;
    }
}
