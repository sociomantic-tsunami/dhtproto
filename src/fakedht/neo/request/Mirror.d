/*******************************************************************************

    Fake DHT node Mirror request implementation.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.neo.request.Mirror;

/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.node.neo.request.Mirror;

import fakedht.neo.SharedResources;
import swarm.neo.node.RequestOnConn;
import swarm.neo.request.Command;

import ocean.meta.types.Qualifiers;

/*******************************************************************************

    Fake node implementation of the v0 Mirror request protocol.

*******************************************************************************/

import fakedht.Storage; // DhtListener

public class MirrorImpl_v0 : MirrorProtocol_v0, DhtListener
{
    import fakedht.Storage;
    import dhtproto.common.RequestCodes : RequestCode;
    import ocean.core.Verify;
    import ocean.core.array.Mutation : copy;
    import ocean.text.convert.Hash : toHashT;

    /// Request code / version. Required by ConnectionHandler.
    static immutable Command command = Command(RequestCode.Mirror, 0);

    /// Request name for stats tracking. Required by ConnectionHandler.
    static immutable istring name = "Mirror";

    /// Flag indicating whether timing stats should be gathered for requests of
    /// this type.
    static immutable bool timing = false;

    /// Flag indicating whether this request type is scheduled for removal. (If
    /// true, clients will be warned.)
    static immutable bool scheduled_for_removal = false;

    /// Reference to channel being mirrored.
    private Channel channel;

    /// Name of channel being mirrored.
    private cstring channel_name;

    /// List of keys to visit during an iteration.
    private istring[] iterate_keys;

    /***************************************************************************

        Performs any logic needed to subscribe to and start mirroring the
        channel of the given name.

        Params:
            channel_name = channel to mirror

        Returns:
            true if the channel may be used, false to abort the request

    ***************************************************************************/

    override protected bool prepareChannel ( cstring channel_name )
    {
        this.channel = global_storage.getCreate(channel_name);
        this.channel_name = channel_name.dup;
        return true;
    }

    /***************************************************************************

        Returns:
            the name of the channel being mirrored (for logging)

    ***************************************************************************/

    override protected cstring channelName ( )
    {
        return this.channel_name;
    }

    /***************************************************************************

        Registers this request to receive updates on the channel.

    ***************************************************************************/

    override protected void registerForUpdates ( )
    {
        verify(this.channel !is null);
        this.channel.register(this);
    }

    /***************************************************************************

        Unregisters this request from receiving updates on the channel.

    ***************************************************************************/

    override protected void unregisterForUpdates ( )
    {
        if (this.channel !is null)
            this.channel.unregister(this);
    }

    /***************************************************************************

        Gets the value of the record with the specified key, if it exists.

        Params:
            key = key of record to get from storage
            buf = buffer to write the value into

        Returns:
            record value or null, if the record does not exist

    ***************************************************************************/

    override protected void[] getRecordValue ( hash_t key, ref void[] buf )
    {
        auto storage_value = this.channel.get(key);
        if ( storage_value is null )
            return null;
        else
        {
            buf.copy(storage_value);
            return buf;
        }
    }

    /***************************************************************************

        Called to begin iterating over the channel being mirrored.

    ***************************************************************************/

    override protected void startIteration ( )
    {
        verify(this.iterate_keys.length == 0, "Iteration already in progress");
        this.iterate_keys = this.channel.getKeys();
    }

    /***************************************************************************

        Adds the next record in the iteration to the update queue, if one
        exists.

        Params:
            hash_key = output value to receive the next key to add to the queue

        Returns:
            true if hash_key was set or false if the iteration is finished

    ***************************************************************************/

    override protected bool iterateNext ( out hash_t hash_key )
    {
        if ( this.iterate_keys.length == 0 )
            return false;

        auto key = this.iterate_keys[$-1];
        this.iterate_keys.length = this.iterate_keys.length - 1;

        auto ok = toHashT(key, hash_key);
        verify(ok);

        return true;
    }

    /***************************************************************************

        DhtListener interface method. Called by Storage when records are
        modified or the channel is deleted.

        Params:
            code = trigger event code
            key  = new dht key

    ***************************************************************************/

    public void trigger ( Code code, cstring key )
    {
        with ( Code ) switch ( code )
        {
            case DataReady:
                hash_t hash_key;
                auto ok = toHashT(key, hash_key);
                verify(ok);

                this.updated(Update(UpdateType.Change, hash_key));
                break;

            case Deletion:
                hash_t hash_key;
                auto ok = toHashT(key, hash_key);
                verify(ok);
                verify(ok);

                this.updated(Update(UpdateType.Deletion, hash_key));
                break;

            case Finish:
                this.channelRemoved();
                break;

            default:
               break;
        }
    }
}
