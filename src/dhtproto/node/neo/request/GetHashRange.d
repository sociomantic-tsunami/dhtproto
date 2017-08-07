/*******************************************************************************

    GetHashRange request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.GetHashRange;

import swarm.neo.AddrPort;

/*******************************************************************************

    Struct containing the details of an update to the hash range (either of
    this node -- if the `self` field is true -- or another node).

*******************************************************************************/

public struct HashRangeUpdate
{
    /// If true, the update relates to this node having changed its hash
    /// range. If false, the update relates to new information about another
    /// node.
    bool self;

    /// IP address/port of other node's neo protocol (only used if self is false).
    AddrPort addr;

    /// New minimum hash.
    hash_t min;

    /// New maximum hash.
    hash_t max;
}


/*******************************************************************************

    v0 GetHashRange request protocol.

*******************************************************************************/

public abstract scope class GetHashRangeProtocol_v0
{
    import swarm.neo.node.RequestOnConn;
    import dhtproto.common.GetHashRange;
    import dhtproto.node.neo.request.core.Mixins;

    import ocean.transition;

    /***************************************************************************

        Mixin the constructor and resources member.

    ***************************************************************************/

    mixin RequestCore!();

    /***************************************************************************

        Codes used when resuming the fiber.

    ***************************************************************************/

    private enum NodeFiberResumeCode : uint
    {
        HashRangeUpdate = 1
    }

    /***************************************************************************

        If true, hashRangeUpdate() (called when either the hash range of this
        node has changed or information about another node is available) resumes
        the fiber.

    ***************************************************************************/

    private bool resume_fiber_on_update;

    /***************************************************************************

        Request-on-conn, to get the event dispatcher and control the fiber.

    ***************************************************************************/

    private RequestOnConn connection;

    /***************************************************************************

        Request handler. Informs the client of the node's current hash range,
        then suspends, waiting for updates to the hash range of this node or
        information about other nodes' hash ranges. When updates are available,
        the request is resumed and a message is sent to the client (one per
        update), forwarding the hash range update.

        Params:
            connection = connection to client
            msg_payload = initial message read from client to begin the request
                (the request code and version are assumed to be extracted)

    ***************************************************************************/

    final public void handle ( RequestOnConn connection, Const!(void)[] msg_payload )
    {
        this.connection = connection;

        hash_t min, max;
        this.getCurrentHashRange(min, max);

        this.registerForHashRangeUpdates();
        scope ( exit )
            this.unregisterForHashRangeUpdates();

        // Send Started status code and current hash range
        auto ed = this.connection.event_dispatcher();
        ed.send(
            ( ed.Payload payload )
            {
                payload.addConstant(RequestStatusCode.Started);
            }
        );

        ed.send(
            ( ed.Payload payload )
            {
                payload.add(min);
                payload.add(max);
            }
        );

        while ( true )
        {
            // Send all pending updates to the client
            HashRangeUpdate update;
            while ( this.getNextHashRangeUpdate(update) )
                this.sendHashRangeUpdate(update);

            // Wait for updates about the hash range
            this.resume_fiber_on_update = true;
            auto resume_code = connection.suspendFiber();
            assert(resume_code == NodeFiberResumeCode.HashRangeUpdate,
                "Unexpected fiber resume code");
            this.resume_fiber_on_update = false;
        }
    }

    /***************************************************************************

        Gets the current hash range of this node.

        Params:
            min = out value where the current minimum hash of this node is stored
            max = out value where the current maximum hash of this node is stored

    ***************************************************************************/

    protected abstract void getCurrentHashRange ( out hash_t min, out hash_t max );

    /***************************************************************************

        Informs the node that this request is now waiting for hash range
        updates. hashRangeUpdate() will be called, when updates are pending.

    ***************************************************************************/

    protected abstract void registerForHashRangeUpdates ( );

    /***************************************************************************

        Informs the node that this request is no longer waiting for hash range
        updates.

    ***************************************************************************/

    protected abstract void unregisterForHashRangeUpdates ( );

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

    protected abstract bool getNextHashRangeUpdate ( out HashRangeUpdate update );

    /***************************************************************************

        Notifies the request when either the hash range of this node has changed
        or information about another node is available. The implementing class
        must call this when notified by the node of this occurring.

    ***************************************************************************/

    final protected void hashRangeUpdate ( )
    {
        if ( this.resume_fiber_on_update )
            this.connection.resumeFiber(NodeFiberResumeCode.HashRangeUpdate);
    }

    /***************************************************************************

        Informs the client about a single hash range update.

        Params:
            update = hash range update to inform client about

    ***************************************************************************/

    private void sendHashRangeUpdate ( HashRangeUpdate update )
    {
        auto ed = this.connection.event_dispatcher();
        ed.send(
            ( ed.Payload payload )
            {
                if ( update.self )
                    payload.addConstant(MessageType.ChangeHashRange);
                else
                {
                    payload.addConstant(MessageType.NewNode);
                    payload.add(update.addr.naddress);
                    payload.add(update.addr.nport);
                }

                payload.add(update.min);
                payload.add(update.max);
            }
        );
    }
}
