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
import swarm.neo.util.VoidBufferAsArrayOf;

/// ditto
public final class NodeHashRanges : NodeHashRangesBase
{
    import swarm.neo.client.ConnectionSet;
    import swarm.neo.client.RequestOnConn;
    import swarm.neo.client.RequestHandlers : UseNodeDg;
    import swarm.neo.AddrPort;

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

        Helper encapsulating the node-selection logic required by requests that
        get a single record from the DHT. Namely:

            During a data redistribution, more than one node may be responsible
            for a given key. In this case, the node that was most recently
            reported as being responsible for the key is queried first, followed
            by others (in order) until the record is located, an error occurs,
            or no node has the record.

        TODO: test the logic for retrying the request on other nodes which
        previously covered the hash. This will require a full neo implementation
        of the Redistribute request. See
        https://github.com/sociomantic-tsunami/dhtnode/issues/21

        Params:
            h = hash to query
            node_hash_ranges = buffer to receive hash range information of
                nodes which cover the specified hash
            use_node = delegate to call to gain access to a request-on-conn to
                communicate with the selected node
            get = delegate to communicate with the selected node (over the
                request-on-conn provided by use_node). Should return true if the
                get succeeded or false to try the next node

    ***************************************************************************/

    public void getFromNode ( hash_t h,
        VoidBufferAsArrayOf!(NodeHashRange) node_hash_ranges, UseNodeDg use_node,
        bool delegate ( RequestOnConn.EventDispatcher ) get )
    {
        auto nodes = this.getNodesForHash(h, node_hash_ranges);
        if ( nodes.length == 0 )
            return;

        foreach ( node_hash_range; nodes.array() )
        {
            bool try_next_node;
            scope conn_dg =
                ( RequestOnConn.EventDispatcher conn )
                {
                    try_next_node = get(conn);
                };
            use_node(node_hash_range.addr, conn_dg);

            // If we got the record or an error occurred, don't try more nodes
            if ( !try_next_node )
                break;
        }
    }

    /***************************************************************************

        Helper encapsulating the node-selection logic required by requests that
        remove a single record from the DHT. Namely:

            During a data redistribution, more than one node may be responsible
            for a given key. In this case, the node that was least recently
            reported as being responsible for the key is queried first, followed
            by others (in order) until the record is either removed from or does
            not exist on all nodes, or an error occurs. The reason for removing
            from the *least* recently responsible nodes first is to avoid
            getting into inconsistent states if an error occurs while removing.
            (If an error occurred when removing the record from the most
            recently responsible node first, subsequent read requests would
            fetch the removed record from older nodes, and the old value could
            be forwarded from an older node, undoing the removal.)

        TODO: test the logic for retrying the request on other nodes which
        previously covered the hash. This will require a full neo implementation
        of the Redistribute request. See
        https://github.com/sociomantic-tsunami/dhtnode/issues/21

        Params:
            h = hash to query
            node_hash_ranges = buffer to receive hash range information of
                nodes which cover the specified hash
            use_node = delegate to call to gain access to a request-on-conn to
                communicate with the selected node
            remove = delegate to communicate with the selected node (over the
                request-on-conn provided by use_node). Should return true if the
                removal succeeded or false on error

    ***************************************************************************/

    public void removeFromNodes ( hash_t h,
        VoidBufferAsArrayOf!(NodeHashRange) node_hash_ranges, UseNodeDg use_node,
        bool delegate ( RequestOnConn.EventDispatcher ) remove )
    {
        auto nodes = this.getNodesForHash(h, node_hash_ranges);
        if ( nodes.length == 0 )
            return;

        foreach_reverse ( node_hash_range; nodes.array() )
        {
            bool continue_to_next_node;
            scope conn_dg =
                ( RequestOnConn.EventDispatcher conn )
                {
                    continue_to_next_node = remove(conn);
                };
            use_node(node_hash_range.addr, conn_dg);

            // If an error occurred, don't try more nodes
            if ( !continue_to_next_node )
                break;
        }
    }

    /***************************************************************************

        Helper encapsulating the node-selection logic required by requests that
        put a single record to the DHT. Namely:

            During a data redistribution, more than one node may be responsible
            for a given key. In this case, the record is written to the node
            that was most recently reported as being responsible for the key.

        Params:
            h = hash to query
            node_hash_ranges = buffer to receive hash range information of
                nodes which cover the specified hash
            use_node = delegate to call to gain access to a request-on-conn to
                communicate with the selected node
            put = delegate to communicate with the selected node (over the
                request-on-conn provided by use_node)

    ***************************************************************************/

    public void putToNode ( hash_t h,
        VoidBufferAsArrayOf!(NodeHashRange) node_hash_ranges, UseNodeDg use_node,
        void delegate ( RequestOnConn.EventDispatcher ) put )
    {
        auto nodes = this.getNodesForHash(h, node_hash_ranges);
        if ( nodes.length == 0 )
            return;

        scope conn_dg =
            ( RequestOnConn.EventDispatcher conn )
            {
                put(conn);
            };
        use_node(nodes.array()[0].addr, conn_dg);
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
    import ocean.core.array.Mutation : sort;
    import ocean.core.Verify;

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
            verify(nhr.addr == addr);
            nhr.hash_range = NodeHashRange.HashRange(min, max);
            nhr.order = order_counter++;
        }
        // Or add a new node.
        else
            this.newNode(addr, min, max);
    }

    /***************************************************************************

        Gets the list of nodes (along with hash range and ordering information)
        which cover the specified hash, sorted (descending) by the values of
        their `order` fields. (This means that the node most recently reported
        as covering the specified hash will appear first in the list.)

        Params:
            h = hash to query
            node_hash_ranges = buffer to receive hash range information of
                nodes which cover the specified hash

        Returns:
            hash range information of nodes which cover the specified hash (a
            slice of node_hash_ranges)

    ***************************************************************************/

    public VoidBufferAsArrayOf!(NodeHashRange) getNodesForHash ( hash_t h,
        VoidBufferAsArrayOf!(NodeHashRange) node_hash_ranges )
    {
        node_hash_ranges.length = 0;

        foreach ( nhr; this.node_hash_ranges )
        {
            if ( isWithinNodeResponsibility(h,
                nhr.hash_range.min, nhr.hash_range.max) )
            {
                node_hash_ranges ~= nhr;
            }
        }

        bool sortPred ( NodeHashRange e1, NodeHashRange e2 )
        {
            verify(e1.order != e2.order);
            return e1.order > e2.order;
        }

        node_hash_ranges.array().sort(&sortPred);

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
    import Integer = ocean.text.convert.Integer_tango;
    import swarm.neo.AddrPort;
    import ocean.core.BitManip : bitswap;

    alias NodeHashRange.HashRange HR;

    void checkTestCase ( VoidBufferAsArrayOf!(NodeHashRange) r1,
        NodeHashRange[] r2, long line_num = __LINE__ )
    {
        auto t = new NamedTest(idup("Test at line " ~ Integer.toString(line_num)));
        t.test!("==")(r1.length, r2.length);

        foreach ( i, e; r1.array() )
        {
            t.test!("==")(e.addr, r2[i].addr);
            t.test!("==")(e.hash_range.min, r2[i].hash_range.min);
            t.test!("==")(e.hash_range.max, r2[i].hash_range.max);
            t.test!("==")(e.order, r2[i].order);
        }
    }
}

// Tests for hash range overlaps and gaps
unittest
{
    auto addr1 = AddrPort(1, 1);
    auto addr2 = AddrPort(2, 2);

    void[] backing;
    auto ranges = VoidBufferAsArrayOf!(NodeHashRange)(&backing);
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
        [NodeHashRange(addr2, HR(0x8000000000000000, hash_t.max), 1),
         NodeHashRange(addr1, HR(hash_t.min, hash_t.max), 0)]);

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

// Tests for hash range ordering
unittest
{
    // Reset ordering counter, as it was modified in other unittests
    NodeHashRangesBase.order_counter = 0;

    auto addr1 = AddrPort(1, 1);
    auto addr2 = AddrPort(2, 2);
    auto addr3 = AddrPort(3, 3);
    auto range = HR(hash_t.min, hash_t.max);

    void[] backing;
    auto ranges = VoidBufferAsArrayOf!(NodeHashRange)(&backing);
    auto hr = new NodeHashRangesBase;

    // Initially empty
    hr.getNodesForHash(0, ranges);
    checkTestCase(ranges, []);

    // One node
    hr.updateNodeHashRange(addr1, range.min, range.max);
    hr.getNodesForHash(0, ranges);
    checkTestCase(ranges,
        [NodeHashRange(addr1, range, 0)]);

    // Add a second node
    hr.updateNodeHashRange(addr2, range.min, range.max);
    hr.getNodesForHash(0, ranges);
    checkTestCase(ranges,
        [NodeHashRange(addr2, range, 1),
         NodeHashRange(addr1, range, 0)]);

    // Add a third node
    hr.updateNodeHashRange(addr3, range.min, range.max);
    hr.getNodesForHash(0, ranges);
    checkTestCase(ranges,
        [NodeHashRange(addr3, range, 2),
         NodeHashRange(addr2, range, 1),
         NodeHashRange(addr1, range, 0)]);

    // Modify the first node
    hr.updateNodeHashRange(addr1, range.min, range.max);
    hr.getNodesForHash(0, ranges);
    checkTestCase(ranges,
        [NodeHashRange(addr1, range, 3),
         NodeHashRange(addr3, range, 2),
         NodeHashRange(addr2, range, 1)]);

    // Modify the third node
    hr.updateNodeHashRange(addr3, range.min, range.max);
    hr.getNodesForHash(0, ranges);
    checkTestCase(ranges,
        [NodeHashRange(addr3, range, 4),
         NodeHashRange(addr1, range, 3),
         NodeHashRange(addr2, range, 1)]);
}
