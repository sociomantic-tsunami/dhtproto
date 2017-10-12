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

import ocean.transition;

/*******************************************************************************

    The request handler for the table of handlers. When called, runs in a fiber
    that can be controlled via `connection`.

    Params:
        shared_resources = an opaque object containing resources owned by the
            node which are required by the request
        connection  = performs connection socket I/O and manages the fiber
        cmdver      = the version number of the Consume command as specified by
                      the client
        msg_payload = the payload of the first message of this request

*******************************************************************************/

public void handle ( Object shared_resources, RequestOnConn connection,
    Command.Version cmdver, Const!(void)[] msg_payload )
{
    auto resources = new SharedResources;

    switch ( cmdver )
    {
        case 0:
            scope rq = new GetAllImpl_v0(resources);
            rq.handle(connection, msg_payload);
            break;

        default:
            auto ed = connection.event_dispatcher;
            ed.send(
                ( ed.Payload payload )
                {
                    payload.addConstant(GlobalStatusCode.RequestVersionNotSupported);
                }
            );
            break;
    }
}

/*******************************************************************************

    Fake node implementation of the v0 GetAll request protocol.

*******************************************************************************/

private scope class GetAllImpl_v0 : GetAllProtocol_v0
{
    import fakedht.Storage;
    import ocean.text.convert.Hash : toHashT;

    /// Reference to channel being iterated over.
    private Channel channel;

    /// List of keys to visit during an iteration.
    private istring[] iterate_keys;

    /***************************************************************************

        Constructor.

        Params:
            shared_resources = DHT request resources getter

    ***************************************************************************/

    public this ( IRequestResources resources )
    {
        super(resources);
    }

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
            assert(ok);
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
            key = receives the key of the next record, if available
            value = receives the value of the next record, if available

        Returns:
            true if a record was returned via the out arguments or false if the
            iteration is finished

    ***************************************************************************/

    override protected bool getNext ( out hash_t key, ref void[] value )
    {
        if ( this.iterate_keys.length == 0 )
            return false;

        auto str_key = this.iterate_keys[$-1];
        this.iterate_keys.length = this.iterate_keys.length - 1;

        auto ok = toHashT(str_key, key);
        assert(ok);
        value = this.channel.get(key).dup;

        return true;
    }
}
