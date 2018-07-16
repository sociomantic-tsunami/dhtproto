/*******************************************************************************

    Protocol base for DHT `PutBatch` request

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.PutBatch;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhtproto.node.request.model.SingleChannel;

/*******************************************************************************

    PutBatch request protocol

*******************************************************************************/

public abstract scope class PutBatch : SingleChannel
{
    import dhtproto.node.request.model.DhtCommand;

    import swarm.util.RecordBatcher;
    import dhtproto.client.legacy.DhtConst;

    /***************************************************************************

        Used to read the records into.

    ***************************************************************************/

    private mstring* record_buffer;

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
        super(DhtConst.Command.E.Listen, reader, writer, resources);
        this.record_buffer = this.resources.getDecompressBuffer();
    }

    /***************************************************************************
        
        Read batch of records to put into the channel

    ***************************************************************************/

    override protected void readChannelRequestData ( )
    {
        if (!this.reader.readArrayLimit(*this.record_buffer, MaximumRecordSize))
        {
            throw this.inputException.set(
                    "Error while reading the batch array: too large");
        }
    }

    /***************************************************************************
    
        Params:
            channel_name = channel name for request that was read and validated
                earlier

    ***************************************************************************/

    final override protected void handleChannelRequest ( cstring channel_name )
    {
        auto decompressor = this.resources.getRecordBatch();
        decompressor.decompress(cast(ubyte[]) *this.record_buffer);

        foreach ( key, value; decompressor )
        {
            if (!value.length)
            {
                this.writer.write(DhtConst.Status.E.EmptyValue);
                return;
            }

            if (!this.isAllowed(key))
            {
                this.writer.write(DhtConst.Status.E.WrongNode);
                return;
            }
            
            if (!this.isSizeAllowed(value.length))
            {
                this.writer.write(DhtConst.Status.E.OutOfMemory);
                return;
            }

            if (!this.putRecord(channel_name, key, value))
            {
                this.writer.write(DhtConst.Status.E.Error);
                return;
            }
        }

        this.writer.write(DhtConst.Status.E.Ok);
    }

    /***************************************************************************

        Verifies that this node is responsible of handling specified record key

        Params:
            key = key to check

        Returns:
            'true' if key is allowed / accepted

    ***************************************************************************/

    abstract protected bool isAllowed ( cstring key );

    /***************************************************************************

        Verifies that this node is allowed to store records of given size

        Params:
            size = size to check

        Returns:
            'true' if size is allowed

    ***************************************************************************/

    abstract protected bool isSizeAllowed ( size_t size );

    /***************************************************************************

        Tries storing record in DHT and reports success status

        Params:
            channel = channel to write record to
            key = record key
            value = record value

        Returns:
            'true' if storing was successful

    ***************************************************************************/

    abstract protected bool putRecord ( cstring channel, cstring key,
        in void[] value );
 }
