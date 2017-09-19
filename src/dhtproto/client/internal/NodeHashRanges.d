/*******************************************************************************

    Class which tracks the hash range associated with a set of nodes, with
    methods to update and query this information. The update method hooks into
    the client's ConnectionSet and adds new connections, as required.

    The order in which the node hash range info is updated is also tracked,
    allowing queries to determine, in the case of a hash range overlap, which is
    the new and which the old node covering this hash range. This information is
    required during DHT redistributions, when nodes may have overlapping hash
    ranges.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.internal.NodeHashRanges;

import ocean.transition;

/// ditto
public final class NodeHashRanges : NodeHashRangesBase
{
    import swarm.neo.client.ConnectionSet;

    /// Set of connections to nodes (one per node)
    private ConnectionSet connections;

    /// Alias for a delegate which receives info about a new node hash-range.
    private alias void delegate ( AddrPort addr, hash_t min, hash_t max )
        NewNodeNotifier;

    /// Delegate called when info about a new node hash-range is available.
    private NewNodeNotifier new_node_dg;

    /***************************************************************************

        Constructor.

        Params:
            connections = ConnectionSet of the client; to be updated by
                updateNodeHashRange(), when applicable
            new_node_dg = delegate called when info about a new node hash-range
                is available

    ***************************************************************************/

    public this ( ConnectionSet connections, NewNodeNotifier new_node_dg )
    {
        this.connections = connections;
        this.new_node_dg = new_node_dg;
    }

    /***************************************************************************

        Adds a new node to the node hash range set and the ConnectionSet.

        Params:
            addr = address & port of new node
            min = minimum hash of new node
            max = maximum hash of new node

    ***************************************************************************/

    override protected void newNode ( AddrPort addr, hash_t min, hash_t max )
    {
        super.newNode(addr, min, max);

        // Also add the new connection to the ConnectionSet, if it's new.
        if ( this.connections.get(addr) is null )
            this.connections.start(addr);

        if ( this.new_node_dg !is null )
        {
            this.new_node_dg(addr, min, max);
        }
    }
}

/*******************************************************************************

    Struct containing information about the hash range of a single node.

*******************************************************************************/

public struct NodeHashRange
{
    import ocean.math.Range;
    import swarm.neo.AddrPort;

    /// Convenience alias for a range of hash_t.
    public alias Range!(hash_t) HashRange;

    /// Address & port of node.
    public AddrPort addr;

    /// Range of hashes covered by node (hash_range.is_empty() may be true).
    public HashRange hash_range;

    /// Ordering integer. Higher numbers were updated more recently.
    public ulong order;
}

/*******************************************************************************

    Base class for NodeHashRanges, without a dependence on the ConnectionSet.
    Purely exists for the sake of unittesting.

*******************************************************************************/

private class NodeHashRangesBase
{
    import ocean.core.Traits : ReturnTypeOf;
    import swarm.neo.AddrPort;
    import swarm.neo.client.ConnectionSet;
    import swarm.util.Hash : isWithinNodeResponsibility;

    /// Value of the next created NodeHashRange's order field.
    private static ulong order_counter;

    /// Convenience alias for the comparison type of AddrPort.
    private alias ReturnTypeOf!(AddrPort.cmp_id) Addr;

    /// Map of IP address -> node hash range.
    private NodeHashRange[Addr] node_hash_ranges;

    /***************************************************************************

        Returns:
            the number of nodes about which hash-range info is known

    ***************************************************************************/

    public size_t length ( )
    {
        return this.node_hash_ranges.length;
    }

    /***************************************************************************

        Adds or modifies the hash range associated with the specified node. If
        the node is not already in the set, it is added and also added to the
        client's ConnectionSet (this.connections).

        Params:
            addr = address & port of node
            min = miniumum hash which the node is responsible for
            max = maxiumum hash which the node is responsible for

    ***************************************************************************/

    public void updateNodeHashRange ( AddrPort addr, hash_t min, hash_t max )
    {
        // Update an existing node.
        if ( auto nhr = addr.cmp_id in this.node_hash_ranges )
        {
            assert(nhr.addr == addr);
            nhr.hash_range = NodeHashRange.HashRange(min, max);
            nhr.order = order_counter++;
        }
        // Or add a new node.
        else
            this.newNode(addr, min, max);
    }

    /***************************************************************************

        Gets the list of nodes (along with hash range and ordering information)
        which cover the specified hash.

        Params:
            h = hash to query
            node_hash_ranges = buffer to receive hash range information of
                nodes which cover the specified hash

        Returns:
            hash range information of nodes which cover the specified hash (a
            slice of node_hash_ranges)

    ***************************************************************************/

    public NodeHashRange[] getNodesForHash ( hash_t h,
        ref NodeHashRange[] node_hash_ranges )
    {
        node_hash_ranges.length = 0;
        enableStomping(node_hash_ranges);

        foreach ( nhr; this.node_hash_ranges )
        {
            if ( isWithinNodeResponsibility(h,
                nhr.hash_range.min, nhr.hash_range.max) )
            {
                node_hash_ranges ~= nhr;
            }
        }

        return node_hash_ranges;
    }

    /***************************************************************************

        Adds a new node to the set. (This method is protected as derived classes
        may wish to add extra behaviour when adding a new node.)

        Params:
            addr = address & port of new node
            min = minimum hash of new node
            max = maximum hash of new node

    ***************************************************************************/

    protected void newNode ( AddrPort addr, hash_t min, hash_t max )
    {
        this.node_hash_ranges[addr.cmp_id] = NodeHashRange(
            addr, NodeHashRange.HashRange(min, max), order_counter++);
    }
}

version ( UnitTest )
{
    import ocean.core.Test;
    import ocean.core.array.Mutation : sort;
    import Integer = ocean.text.convert.Integer_tango;
    import swarm.neo.AddrPort;
    import ocean.core.BitManip : bitswap;
}

unittest
{
    alias NodeHashRange.HashRange HR;

    void checkTestCase ( NodeHashRange[] r1, NodeHashRange[] r2, long line_num = __LINE__ )
    {
        auto t = new NamedTest(idup("Test at line " ~ Integer.toString(line_num)));
        t.test!("==")(r1.length, r2.length);

        bool sortPred ( NodeHashRange e1, NodeHashRange e2 )
        {
            return e1.addr.cmp_id < e2.addr.cmp_id;
        }

        // Ordering doesn't matter, so we sort both arrays
        r1.sort(&sortPred);
        r2.sort(&sortPred);

        foreach ( i, e; r1 )
        {
            t.test!("==")(e.addr, r2[i].addr);
            t.test!("==")(e.hash_range.min, r2[i].hash_range.min);
            t.test!("==")(e.hash_range.max, r2[i].hash_range.max);
            t.test!("==")(e.order, r2[i].order);
        }
    }

    auto addr1 = AddrPort(1, 1);
    auto addr2 = AddrPort(2, 2);

    NodeHashRange[] ranges;
    auto hr = new NodeHashRangesBase;

    // Initially empty
    hr.getNodesForHash(0, ranges);
    checkTestCase(ranges, []);

    // One node covering the whole range
    hr.updateNodeHashRange(addr1, hash_t.min, hash_t.max);
    hr.getNodesForHash(0, ranges);
    checkTestCase(ranges,
        [NodeHashRange(addr1, HR(hash_t.min, hash_t.max), 0)]);

    // A second node covering half the range (overlap)
    hr.updateNodeHashRange(addr2, 0x8000000000000000, hash_t.max);
    hr.getNodesForHash(0, ranges);
    checkTestCase(ranges,
        [NodeHashRange(addr1, HR(hash_t.min, hash_t.max), 0)]);
    hr.getNodesForHash(hash_t.max, ranges);
    checkTestCase(ranges,
        [NodeHashRange(addr1, HR(hash_t.min, hash_t.max), 0),
         NodeHashRange(addr2, HR(0x8000000000000000, hash_t.max), 1)]);

    // Change the range of the first node to cover the other half of the range
    hr.updateNodeHashRange(addr1, hash_t.min, 0x7fffffffffffffff);
    hr.getNodesForHash(0, ranges);
    checkTestCase(ranges,
        [NodeHashRange(addr1, HR(hash_t.min, 0x7fffffffffffffff), 2)]);
    hr.getNodesForHash(hash_t.max, ranges);
    checkTestCase(ranges,
        [NodeHashRange(addr2, HR(0x8000000000000000, hash_t.max), 1)]);

    // Change the range of the second node to create a gap
    // (Note that bitswap is used to mimic the internal behaviour of
    // isWithinNodeResponsibility, used in getNodesForHash.)
    hr.updateNodeHashRange(addr2, 0x9000000000000000, hash_t.max);
    hr.getNodesForHash(bitswap(0x8000000000000000), ranges);
    checkTestCase(ranges, []);
    hr.getNodesForHash(hash_t.max, ranges);
    checkTestCase(ranges,
        [NodeHashRange(addr2, HR(0x9000000000000000, hash_t.max), 3)]);
}
