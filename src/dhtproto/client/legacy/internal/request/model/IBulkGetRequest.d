/*******************************************************************************

    Base class for asynchronously/Selector managed DHT bulk get requests
    (GetAll, GetRange, GetAllKeys)

    The bulk dht commands all return compressed batches of values. This base
    class implements the functionality to receive these batches and to extract
    the records contained with them.

    All bulk requests also have the facility for being suspended / resumed by
    the user of the DhtClient.

    Copyright:
        Copyright (c) 2011-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.request.model.IBulkGetRequest;



/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import swarm.Const : NodeItem;

import swarm.common.request.helper.LoopCeder;

import swarm.client.request.model.IStreamInfo;

import swarm.client.request.helper.RequestSuspender;

import dhtproto.client.legacy.internal.request.model.IChannelRequest;

import ocean.core.Verify;

import ocean.core.VersionCheck;

import ocean.io.select.client.FiberSelectEvent;

import ocean.io.compress.lzo.LzoChunkCompressor;




/*******************************************************************************

    IBulkGetRequest abstract base class

*******************************************************************************/

abstract private class IBulkGetRequest : IChannelRequest, IStreamInfo
{
    /***************************************************************************

        Total bytes handled by this request.

    ***************************************************************************/

    private size_t bytes_handled_;


    /***************************************************************************

        Constructor.

        Note: the same FiberSelectEvent is used for both user-requested
        suspension of the bulk request, and for ceding of the request to allow
        other select clients to be handled. This is perfectly fine, as the fiber
        is strictly sequential.

        Params:
            reader = fiber select reader instance to use for read requests
            writer = fiber select writer instance to use for write requests
            resources = shared resources which might be required by the request

    ***************************************************************************/

    public this ( FiberSelectReader reader, FiberSelectWriter writer,
        IDhtRequestResources resources )
    {
        super(reader, writer, resources);
    }


    /***************************************************************************

        Returns:
            the number of bytes sent/received by the stream (we currently assume
            that a stream request is either sending or receiving)

    ***************************************************************************/

    override public size_t bytes_handled ( )
    {
        return this.bytes_handled_;
    }


    /***************************************************************************

        Returns:
            the nodeitem this producer is associated with

    ***************************************************************************/

    override public NodeItem nodeitem ( )
    {
        return NodeItem(this.resources.conn_pool_info.address,
            this.resources.conn_pool_info.port);
    }


    /***************************************************************************

        Handles a request once the request data has been sent and a valid status
        has been received from the node.

        Note: the reader cedes after processing every batch, in order to avoid
        the odd situation where multiple bulk requests are running at the same
        time, and, due to the order in which epoll handles the file decriptors,
        one of the requests may receive far more processing time than the
        others.

    ***************************************************************************/

    final override protected void handle__ ( )
    {
        this.resources.request_suspender.start();

        // Pass suspendable interface to user.
        if ( this.params.suspend_register !is null )
        {
            this.params.suspend_register(this.params.context,
                this.resources.request_suspender);
        }

        scope (exit)
        {
            if ( this.params.suspend_unregister !is null )
            {
                verify(this.params.suspend_register !is null);
                this.params.suspend_unregister(this.params.context,
                    this.resources.request_suspender);
            }
        }

        // Pass stream info interface to user.
        if ( this.params.stream_info_register !is null )
        {
            this.params.stream_info_register(this.params.context, this);
        }

        bool received_batch;
        do
        {
            received_batch = this.readBatch();

            auto suspended = this.resources.request_suspender.handleSuspension();
            if ( !suspended && received_batch )
            {
                this.resources.loop_ceder.handleCeding();
            }
        }
        while ( received_batch ); // end upon receiving ""
    }


    /***************************************************************************

        Reads the next batch of records from the node, and calls the
        processBatch() method if the received batch is of non-0 length. (A batch
        of 0 length indicates end of stream.)

        Returns:
            true if a batch was received, false if "" was received (indicating
            end of stream)

    ***************************************************************************/

    private bool readBatch ( )
    {
        this.reader.readArray(*this.resources.batch_buffer);

        if ( this.resources.batch_buffer.length )
        {
            this.bytes_handled_ += this.resources.batch_buffer.length;

            this.processBatch(*this.resources.batch_buffer);

            return true;
        }

        return false;
    }


    /***************************************************************************

        Processes a received batch of records.

        Params:
            batch = batch received (still compressed)

    ***************************************************************************/

    abstract protected void processBatch ( in char[] batch );
}



/*******************************************************************************

    Base class for bulk requests which handle paired values.

*******************************************************************************/

abstract public scope class IBulkGetPairsRequest : IBulkGetRequest
{
    /***************************************************************************

        Constructor.

        Params:
            reader = fiber select reader instance to use for read requests
            writer = fiber select writer instance to use for write requests
            resources = shared resources which might be required by the request

    ***************************************************************************/

    public this ( FiberSelectReader reader, FiberSelectWriter writer,
        IDhtRequestResources resources )
    {
        super(reader, writer, resources);
    }


    /***************************************************************************

        Processes a received batch of records.

        Params:
            batch = batch received (still compressed)

    ***************************************************************************/

    final override protected void processBatch ( in char[] batch )
    {
        void receivePair ( in char[] value1, in char[] value2 )
        {
            this.processPair(value1, value2);
            this.resources.request_suspender.handleSuspension();
        }

        this.resources.record_batch.decompress(cast(const(ubyte)[])batch);
        foreach ( key, value; this.resources.record_batch )
        {
            receivePair(key, value);
        }
    }


    /***************************************************************************

        Processes a received pair (typically a key/value pair).

        Params:
            value1 = 1st value extracted from batch
            value2 = 2nd value extracted from batch

    ***************************************************************************/

    abstract protected void processPair ( in char[] value1, in char[] value2 );
}



/*******************************************************************************

    Base class for bulk requests which handle single values.

*******************************************************************************/

abstract public scope class IBulkGetValuesRequest : IBulkGetRequest
{
    /***************************************************************************

        Constructor.

        Params:
            reader = fiber select reader instance to use for read requests
            writer = fiber select writer instance to use for write requests
            resources = shared resources which might be required by the request

    ***************************************************************************/

    public this ( FiberSelectReader reader, FiberSelectWriter writer,
        IDhtRequestResources resources )
    {
        super(reader, writer, resources);
    }


    /***************************************************************************

        Processes a received batch of records.

        Params:
            batch = batch received (still compressed)

    ***************************************************************************/

    final override protected void processBatch ( in char[] batch )
    {
        void receiveValue ( in char[] value )
        {
            this.processValue(value);

            this.resources.request_suspender.handleSuspension();
        }

        this.resources.record_batch.decompress(cast(const(ubyte)[])batch);
        foreach ( value; this.resources.record_batch )
        {
            receiveValue(value);
        }
    }


    /***************************************************************************

        Processes a received value.

        Params:
            value = value extracted from batch

    ***************************************************************************/

    abstract protected void processValue ( in char[] value );
}
