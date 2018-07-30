/*******************************************************************************

    Protocol base for DHT `Redistribute` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.Redistribute;

/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.node.request.model.DhtCommand;

import ocean.util.log.Logger;
import ocean.transition;

/*******************************************************************************

    Static module logger

*******************************************************************************/

private Logger log;

static this ( )
{
    log = Log.lookup("dhtproto.node.request.Redistribute");
}

/*******************************************************************************

    Request protocol

*******************************************************************************/

public abstract scope class Redistribute : DhtCommand
{
    import dhtproto.node.request.params.RedistributeNode;

    import dhtproto.client.legacy.DhtConst;
    import Hash = swarm.util.Hash;

    /***************************************************************************

        Only a single Redistribute request may be handled at a time. This global
        counter is incremented in the ctor and decremented in the dtor. The
        handler method checks that is it == 1, and returns an error code to
        the client otherwise.

    ***************************************************************************/

    private static uint instance_count;

    /***************************************************************************

        New minimum and maximum hash range for this node. Received from the
        client which sent the request.

    ***************************************************************************/

    private hash_t min, max;

    /***************************************************************************
        
        Pointer to external data buffer used to store incoming redistribution
        data

    ***************************************************************************/

    private RedistributeNode[]* redistribute_node_buffer;

    /***************************************************************************

        Constructor

        Params:
            reader = FiberSelectReader instance to use for read requests
            writer = FiberSelectWriter instance to use for write requests
            resources = object providing resource getters

    ***************************************************************************/

    public this ( FiberSelectReader reader, FiberSelectWriter writer,
        DhtCommand.Resources resources ) 
    {
        super(DhtConst.Command.E.Redistribute, reader, writer, resources);
        this.redistribute_node_buffer = this.resources.getRedistributeNodeBuffer();
        ++this.instance_count;
    }

    /***************************************************************************
    
        Destructor (relies on this being a scope class)

    ***************************************************************************/

    ~this()
    {
        --this.instance_count;
    }

    /***************************************************************************

        Reads redistribution data and does basic deserialization.

        NB! This does not do hash range validation

    ***************************************************************************/

    final override protected void readRequestData ( )
    {
        this.reader.read(this.min);
        this.reader.read(this.max);
        log.trace("New hash range: 0x{:x16}..0x{:x16}", this.min, this.max);

        (*this.redistribute_node_buffer).length = 0;
        enableStomping(*this.redistribute_node_buffer);

        while (true)
        {
            (*this.redistribute_node_buffer).length =
                (*this.redistribute_node_buffer).length + 1;
            auto next = &((*this.redistribute_node_buffer)[$-1]);

            this.reader.readArray(next.node.Address);
            if (next.node.Address.length == 0)
                break;
            this.reader.read(next.node.Port);

            hash_t min, max;
            this.reader.read(min);
            this.reader.read(max);
            log.trace("Forward to node {}:{} 0x{:x16}..0x{:x16}",
                next.node.Address, next.node.Port, min, max);
            next.range = Hash.HashRange(min, max);
        }

        // Cut off final "end of flow" marker
        (*this.redistribute_node_buffer).length =
            (*this.redistribute_node_buffer).length - 1;
        enableStomping(*this.redistribute_node_buffer);
    }

    /***************************************************************************
    
        Validates hash ranges and forward to derivative methods to do actual
        redistribution which is 100% implementation-defined

    ***************************************************************************/

    final override protected void handleRequest ( )
    {
        if (this.instance_count > 1)
        {
            log.error("Attempt to start multiple simultaneous Redistribute requests");
            this.writer.write(DhtConst.Status.E.Error);
            return;
        }

        if (!Hash.HashRange.isValid(this.min, this.max))
        {
            log.error("Received invalid hash range from client");
            this.writer.write(DhtConst.Status.E.Error);
            return;
        }

        // TODO: check that the new range of this node plus the ranges of the
        // other nodes completely cover (are a superset of) the old range of
        // this node. Return an error code otherwise.
        // This will require the list of new nodes to be sorted by hash range.

        foreach (node; *this.redistribute_node_buffer)
        {
            if (!Hash.HashRange.isValid(
                node.range.min, node.range.max))
            {
                log.error("Hash range for a node is invalid");
                this.writer.write(DhtConst.Status.E.Error);
                return;
            }
        }

        this.writer.write(DhtConst.Status.E.Ok);

        this.adjustHashRange(this.min, this.max);
        this.redistributeData(*this.redistribute_node_buffer);
    }

    /***************************************************************************

        Adjust storage resources if necessary to handle given hash range for
        upcoming redistribution

        Params:
            min = minimal hash value for expected dataset
            max = maximal hash value for expected dataset

    ***************************************************************************/

    abstract protected void adjustHashRange ( hash_t min, hash_t max );

    /***************************************************************************

        Process actual redistribution in an implementation-defined way

    ***************************************************************************/

    abstract protected void redistributeData ( RedistributeNode[] dataset );
}
