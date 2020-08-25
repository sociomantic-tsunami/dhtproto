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

import ocean.meta.types.Qualifiers;

/*******************************************************************************

    Fake node implementation of the v0 GetHashRange request protocol.

*******************************************************************************/

public class GetHashRangeImpl_v0 : GetHashRangeProtocol_v0
{
    import dhtproto.common.RequestCodes : RequestCode;

    /// Request code / version. Required by ConnectionHandler.
    static immutable Command command = Command(RequestCode.GetHashRange, 0);

    /// Request name for stats tracking. Required by ConnectionHandler.
    static immutable string name = "GetHashRange";

    /// Flag indicating whether timing stats should be gathered for requests of
    /// this type.
    static immutable bool timing = false;

    /// Flag indicating whether this request type is scheduled for removal. (If
    /// true, clients will be warned.)
    static immutable bool scheduled_for_removal = false;

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
