/*******************************************************************************

    Fake DHT node GetHashRange request implementation.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.neo.request.GetHashRange;

/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.node.neo.request.GetHashRange;

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
            scope rq = new GetHashRangeImpl_v0(resources);
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

    Fake node implementation of the v0 GetHashRange request protocol.

*******************************************************************************/

private scope class GetHashRangeImpl_v0 : GetHashRangeProtocol_v0
{
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

        Gets the current hash range of this node.

        Params:
            min = out value where the current minimum hash of this node is stored
            max = out value where the current maximum hash of this node is stored

    ***************************************************************************/

    override protected void getCurrentHashRange ( out hash_t min, out hash_t max )
    {
        min = hash_t.min;
        max = hash_t.max;
    }

    /***************************************************************************

        Informs the node that this request is now waiting for hash range
        updates. hashRangeUpdate() will be called, when updates are pending.

    ***************************************************************************/

    override protected void registerForHashRangeUpdates ( )
    {
        // The fake DHT node currently does not handle forwarding of hash range
        // updates to the client.
    }

    /***************************************************************************

        Informs the node that this request is no longer waiting for hash range
        updates.

    ***************************************************************************/

    override protected void unregisterForHashRangeUpdates ( )
    {
        // The fake DHT node currently does not handle forwarding of hash range
        // updates to the client.
    }

    /***************************************************************************

        Gets the next pending hash range update (or returns false, if no updates
        are pending). The implementing node should store a queue of updates per
        GetHashRange request and feed them to the request, in order, when this
        method is called.

        Params:
            update = out value to receive the next pending update, if one is
                available

        Returns:
            false if no update is pending

    ***************************************************************************/

    override protected bool getNextHashRangeUpdate ( out HashRangeUpdate update )
    {
        // The fake DHT node currently does not handle forwarding of hash range
        // updates to the client.
        return false;
    }
}
