/*******************************************************************************

    Classes for maintaining batches of records destined to be sent to particular
    dht nodes.

    Copyright:
        Copyright (c) 2014-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.common.NodeRecordBatcher;



/*******************************************************************************

    Imports

*******************************************************************************/

import swarm.util.RecordBatcher;

import Hash = swarm.util.Hash;

import dhtproto.client.legacy.DhtConst;

import dhtproto.client.legacy.internal.registry.model.IDhtNodeRegistryInfo;

import ocean.io.compress.Lzo;

import ocean.util.container.pool.FreeList;

import ocean.util.container.map.Map;

import ocean.transition;
import ocean.core.Verify;


/*******************************************************************************

    Reusable batch of records associated with a particular node address/port.
    Records are added via the add() method and removed by calling compress() or
    clear().

    A list of hashes of records currently stored in the batch is also
    maintained for iteration.

    In order to allow the class to be reused with different dhts, the (required)
    node address/port and node registry interface are provided via the reset()
    method, rather than via the constructor.

*******************************************************************************/

public class NodeRecordBatcher
{
    /***************************************************************************

        Node to batch records for

    ***************************************************************************/

    private DhtConst.NodeItem node;


    /***************************************************************************

        Batch of records for this node

    ***************************************************************************/

    private RecordBatcher batcher;


    /***************************************************************************

        Dht client registry to look up node responsibility for hashes

    ***************************************************************************/

    private IDhtNodeRegistryInfo registry;


    /***************************************************************************

        List of hashes of records currently contained in the batch. Provides a
        single public method -- an iterator accessible via the public
        batched_hashes member.

    ***************************************************************************/

    struct BatchedHashes
    {
        private hash_t[] hashes;

        public int opApply ( scope int delegate ( ref hash_t hash ) dg )
        {
            int r;
            foreach ( h; (&this).hashes )
            {
                r = dg(h);
                if ( r ) break;
            }
            return r;
        }
    }

    public BatchedHashes batched_hashes;


    /***************************************************************************

        Result codes for add() methods. "Derives" from the enum of the same name
        in RecordBatcher, plus adds an additional value.

    ***************************************************************************/

    public enum AddResult : int
    {
        None        = RecordBatcher.AddResult.None,
        Added       = RecordBatcher.AddResult.Added,
        BatchFull   = RecordBatcher.AddResult.BatchFull,
        TooBig      = RecordBatcher.AddResult.TooBig,
        WrongNode
    }


    /***************************************************************************

        Constructor.

        Params:
            lzo = lzo de/compressor to use

    ***************************************************************************/

    public this ( Lzo lzo )
    {
        this.batcher = new RecordBatcher(lzo);
    }


    /***************************************************************************

        Initialises / resets this instance, ready for (re)use. All records are
        cleared from the batch.

        Params:
            node = address/port of node to batch records for
            registry = node registry interface

    ***************************************************************************/

    public void reset ( DhtConst.NodeItem node, IDhtNodeRegistryInfo registry )
    {
        this.node = node;
        this.registry = registry;
        this.clear();
    }


    /***************************************************************************

        Returns:
            address of node for which this batcher is collecting records

    ***************************************************************************/

    public mstring address ( )
    {
        return this.node.Address;
    }


    /***************************************************************************

        Returns:
            port of node for which this batcher is collecting records

    ***************************************************************************/

    public ushort port ( )
    {
        return this.node.Port;
    }


    /***************************************************************************

        Checks whether the specified key/value would fit in the batch.

        Params:
            key = key to check
            value = value to check

        Returns:
            true if the key/value would fit, false if it's too big

    ***************************************************************************/

    public bool fits ( cstring key, cstring value )
    {
        return this.batcher.fits(key, value);
    }


    /***************************************************************************

        Checks whether the specified key/value would fit in the currently
        available free space in the batch. Also returns, via an out parameter,
        whether it is impossible for the key/value to fit in the batch, even
        when it's empty.

        Params:
            key = key to check
            value = value to check
            will_never_fit = output value, set to true if the key/value are
                larger than the batch buffer's dimension (meaning that the
                key/value can never fit in the batch, even when it's empty)

        Returns:
            true if the key/value would fit in the current free space, false if
            they're too big

    ***************************************************************************/

    public bool fits ( cstring key, cstring value, out bool will_never_fit )
    {
        return this.batcher.fits(key, value, will_never_fit);
    }


    /***************************************************************************

        Adds a key/value pair to the batch. If the pair is added to the batch,
        the hash (the converted key) is added to the list of stored hashes.

        Params:
            key = key to add
            value = value to add

        Returns:
            code indicating result of add

    ***************************************************************************/

    public AddResult add ( cstring key, cstring value )
    {
        verify(this.node.Address.length != 0);
        verify(this.registry !is null);

        auto hash = Hash.straightToHash(key);
        auto responsible_node = this.registry.responsibleNode(hash);
        if ( responsible_node.address != this.node.Address ||
            responsible_node.port != this.node.Port )
        {
            return AddResult.WrongNode;
        }

        AddResult add_result = cast(AddResult)this.batcher.add(key, value);

        if ( add_result == AddResult.Added )
        {
            this.batched_hashes.hashes ~= hash;
        }

        return add_result;
    }


    /***************************************************************************

        Returns:
            the number of records stored in the batch

    ***************************************************************************/

    public size_t length ( )
    {
        return this.batched_hashes.hashes.length;
    }


    /***************************************************************************

        Compresses the batch into the provided buffer. The first size_t.sizeof
        bytes of the destination buffer contain the uncompressed length of the
        batch, which is needed for decompression.

        Once the batch has been compressed into the provided buffer, the batch
        is cleared, to be ready for re-use. The list of batched hashes is not
        cleared -- this must be done manually by calling clear().

        Params:
            compress_buf = buffer to receive compressed data

        Returns:
            compress_buf, containing the compressed data

    ***************************************************************************/

    public ubyte[] compress ( ref ubyte[] compress_buf )
    {
        return this.batcher.compress(compress_buf);
    }


    /***************************************************************************

        Clears the batch and the list of stored hashes.

    ***************************************************************************/

    public void clear ( )
    {
        this.batcher.clear();
        this.batched_hashes.hashes.length = 0;
    }
}


/*******************************************************************************

    Reusable set of record batchers indexed by node address/port. Record
    batchers are added to the set via the batch() getter and are removed
    (recycled for later reuse) via the reset() method.

    In order to allow the class to be reused with different dhts, the (required)
    node registry interface is provided via the reset() method, rather than via
    the constructor.

*******************************************************************************/

public class NodeRecordBatcherMap
{
    /***************************************************************************

        Pool of reusable NodeRecordBatcher instances

    ***************************************************************************/

    private alias FreeList!(NodeRecordBatcher) Pool;

    private Pool pool;


    /***************************************************************************

        Map from node address/port to NodeRecordBatcher instance

    ***************************************************************************/

    private alias StandardKeyHashingMap!(NodeRecordBatcher, DhtConst.NodeItem) Map;

    private Map map;


    /***************************************************************************

        Lzo instance shared by all record batchers in the map/pool

    ***************************************************************************/

    private Lzo lzo;


    /***************************************************************************

        Dht node registry interface, required by the record batchers. Set via
        the reset() method, rather than the ctor, in order to allow the class to
        be reused with different dhts.

    ***************************************************************************/

    private IDhtNodeRegistryInfo registry;


    /***************************************************************************

        Constructor.

        Params:
            lzo = lzo de/compressor to use
            estimated_num_entires = estimate of the number of entries expected
                in the map. This value is used to initialise the number of
                buckets in the internal map, so only affects the performance of
                lookups -- it is not a hard limit

    ***************************************************************************/

    public this ( Lzo lzo, uint estimated_num_entires )
    {
        this.lzo = lzo;

        this.pool = new Pool;
        this.map = new Map(estimated_num_entires);
    }


    /***************************************************************************

        Initialises / resets this instance, ready for (re)use. All existing
        batches are cleared and recylced.

        Params:
            registry = node registry interface

    ***************************************************************************/

    public void reset ( IDhtNodeRegistryInfo registry )
    {
        this.registry = registry;

        foreach ( k, v; this.map )
        {
            v.clear();
            this.pool.recycle(v);
        }
        this.map.clear();
    }


    /***************************************************************************

        Map index operator to look up a batch by node address/port. If no batch
        exists for the specified node, a new one is created.

        Params:
            node = address/port of node to fetch batch for

    ***************************************************************************/

    public NodeRecordBatcher opIndex ( DhtConst.NodeItem node )
    {
        verify(this.registry !is null);

        NodeRecordBatcher* batch = node in this.map;
        if ( batch is null )
        {
            auto new_batch = this.pool.get(new NodeRecordBatcher(this.lzo));
            *this.map.put(node) = new_batch;
            batch = &new_batch;
            batch.reset(node, this.registry);
        }
        verify(batch !is null);

        return *batch;
    }
}
