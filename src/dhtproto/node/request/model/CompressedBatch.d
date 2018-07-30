/*******************************************************************************

    Abstract base class for dht node that implements efficient async sending
    of chunks of derivative-defined data to the client. Each chunk is sent in
    separate compressed batch thus the class name.

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.model.CompressedBatch;

/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.node.request.model.SingleChannel;

import ocean.transition;
import ocean.core.Verify;
import ocean.util.log.Logger;

/*******************************************************************************

    Static module logger

*******************************************************************************/

static private Logger log;

static this ( )
{
    log = Log.lookup("dhtproto.node.request.model.CompressedBatch");
}

/*******************************************************************************

    Abstract common implementation for compressed batch requests

    Template Params:
        T... = types of data that gets added to batch in one chunk. So far it
            is always CompressedBatch!(mstring) for just keys or
            CompressedBatch!(mstring, mstring) for key + value pairs.

*******************************************************************************/

public abstract scope class CompressedBatch(T...) : SingleChannel
{
    import dhtproto.node.request.model.DhtCommand;

    import dhtproto.client.legacy.DhtConst;
    import swarm.util.RecordBatcher;

    /***************************************************************************

        Object used to do data compression. Ackquired from resources.

        Intermediate data is stored inside batcher object while it
        is aggregated for compression.

    ***************************************************************************/

    private RecordBatcher batcher;

    /***************************************************************************

        Used as target buffer for compressed data. Needs to be persistent
        because fiber switch can happen while writing the chunk to the socket.

    ***************************************************************************/

    private ubyte[]* compressed_data;

    /***************************************************************************

        Constructor

        Params:
            cmd = command code
            reader = FiberSelectReader instance to use for read requests
            writer = FiberSelectWriter instance to use for write requests
            resources = object providing resource getters

    ***************************************************************************/

    public this ( DhtConst.Command.E cmd, FiberSelectReader reader,
        FiberSelectWriter writer, DhtCommand.Resources resources )
    {
        super(cmd, reader, writer, resources);
        this.batcher = this.resources.getRecordBatcher();
        this.compressed_data = this.resources.getCompressBuffer();
    }

    /***************************************************************************

        Defined compressed batch request protocol in generic way. Actual data
        send depends on request type and input parameters but responses
        always get packed in compressed chunks.

        Params:
            channel_name = channel name for request that was read and validated
                earlier
        
    ***************************************************************************/

    final override protected void handleChannelRequest ( cstring channel_name )
    {
        this.writer.write(DhtConst.Status.E.Ok);

        T args; // NB: this is variable list

        void writeBatch ( )
        {
            this.batcher.compress(*this.compressed_data);

            if (this.compressed_data.length)
                this.writer.writeArray(*this.compressed_data);
        }

        while (this.getNext(args))
        {
            auto add_result = this.batcher.add(args);

            switch (add_result) with (RecordBatcher.AddResult)
            {
                case Added:
                    // all good, can add more data to batch
                    break;
                case BatchFull:
                    // new record does not fit into this batch, send it and
                    // add the record to new batch
                    writeBatch();
                    add_result = this.batcher.add(args);
                    verify(add_result == Added);
                    break;
                case TooBig:
                    // impossible to fit the record even in empty batch
                    log.warn(
                        "Large record ({} bytes) being skipped for "
                            ~ " compressed batch request on {} ",
                        total_length(args),
                        channel_name
                    );
                    break;
                default:
                    assert(false, "Invalid AddResult in switch");
            }
        }
        
        // handle last pending batch at the end of iteration (does nothing if no records are pending)
        writeBatch();

        // empty array indicates end of data
        this.writer.writeArray("");
    }

    /***************************************************************************
        
        Returns current record to be sent to the client. May handle fiber
        context switches and event loop internally if necessary. Always returns
        same record until this.fetchNext gets called.

        Params:
            args = filled with data to be sent to the client. It does not need
                to be persistent as it is copied into internal batch buffer

        Returns:
            `true` is there will be more data, `false` if this was last chunk

    ***************************************************************************/

    abstract protected bool getNext ( out T args );
}

/******************************************************************************

    Params:
        args = variadic list of array arguments 

    Returns:
        length of largest array among arguments

******************************************************************************/

private size_t total_length ( ARGS... ) ( ARGS args )
{
    size_t size = 0;

    foreach (ref arg; args)
        size += arg.length;

    return size;
}
