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
    auto ed = connection.event_dispatcher;

    switch ( cmdver )
    {
        case 0:
            ed.send(
                ( ed.Payload payload )
                {
                    payload.addConstant(SupportedStatus.RequestSupported);
                }
            );

            scope rq = new PutImpl_v0(resources);
            rq.handle(connection, msg_payload);
            break;

        default:
            ed.send(
                ( ed.Payload payload )
                {
                    payload.addConstant(SupportedStatus.RequestVersionNotSupported);
                }
            );
            break;
    }
}

/*******************************************************************************

    Fake node implementation of the v0 Put request protocol.

*******************************************************************************/

private scope class PutImpl_v0 : PutProtocol_v0
{
    import fakedht.Storage;

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
