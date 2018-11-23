/*******************************************************************************

    Asynchronously/Selector managed dht Listen request class

    Processes the dht node's output after a Listen command, and forwards the
    received values to the provided output delegate.

    Copyright:
        Copyright (c) 2011-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.request.ListenRequest;



/*******************************************************************************

    Imports

*******************************************************************************/

import swarm.Const : NodeItem;

import dhtproto.client.legacy.internal.request.model.IChannelRequest;

import swarm.common.request.helper.LoopCeder;

import swarm.client.request.model.IStreamInfo;

import swarm.client.request.helper.RequestSuspender;

import ocean.io.select.client.FiberSelectEvent;




/*******************************************************************************

    ListenRequest class

*******************************************************************************/

public scope class ListenRequest : IChannelRequest, IStreamInfo
{
    /***************************************************************************

        Total bytes handled by this request.

    ***************************************************************************/

    private size_t bytes_handled_;


    /***************************************************************************

        Constructor

        Params:
            reader = FiberSelectReader instance to use for read requests
            writer = FiberSelectWriter instance to use for write requests
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

        Sends the node any data required by the request.

        The base class has already sent the command & channel, so this request
        needs send nothing more.

    ***************************************************************************/

    override protected void sendRequestData__ ( )
    {
    }


    /***************************************************************************

        Handles the request once the request data has been sent and a valid
        status has been received from the node.

    ***************************************************************************/

    override protected void handle__ ( )
    {
        // Pass suspendable interface to user.
        if ( this.params.suspend_register !is null )
        {
            this.params.suspend_register(this.params.context,
                this.resources.request_suspender);
        }

        this.resources.request_suspender.start();

        // Pass stream info interface to user.
        if ( this.params.stream_info_register !is null )
        {
            this.params.stream_info_register(this.params.context, this);
        }

        // Get output delegate
        auto output = params.io_item.get_pair();

        do
        {
            // Read key & value
            this.reader.readArray(*this.resources.key_buffer);
            this.reader.readArray(*this.resources.value_buffer);

            // Forward value (unless end-of-flow marker)
            if ( this.resources.key_buffer.length )
            {
				this.bytes_handled_ += this.resources.key_buffer.length;
				this.bytes_handled_ += this.resources.value_buffer.length;

                output(this.params.context, *this.resources.key_buffer,
                    *this.resources.value_buffer);
            }

            // Suspend, if requested
            auto suspended = this.resources.request_suspender.handleSuspension();
            if ( !suspended )
            {
                this.resources.loop_ceder.handleCeding();
            }
        }
        while ( this.resources.key_buffer.length );
    }
}

