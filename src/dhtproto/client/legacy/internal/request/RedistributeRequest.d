/*******************************************************************************

    Redistribute request class.

    Copyright:
        Copyright (c) 2014-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.request.RedistributeRequest;



/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.client.legacy.internal.request.model.IRequest;



/*******************************************************************************

    Redistribute request

*******************************************************************************/

public scope class RedistributeRequest : IRequest
{
    /**************************************************************************

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

        Sends the node any data required by the request.

    ***************************************************************************/

    override protected void sendRequestData_ ( )
    {
        auto input = params.io_item.redistribute();
        auto redist_info = input(this.params.context);

        with ( redist_info.new_range )
        {
            this.writer.write(min);
            this.writer.write(max);
        }

        for ( size_t i; i < redist_info.redist_nodes.length; i++ )
        {
            with ( redist_info.redist_nodes[i] )
            {
                this.writer.writeArray(node.Address);
                this.writer.write(node.Port);
                this.writer.write(range.min);
                this.writer.write(range.max);
            }
        }

        this.writer.writeArray(""); // end of list
    }


    /***************************************************************************

        Handles a request once the request data has been sent and a valid status
        has been received from the node.

    ***************************************************************************/

    override protected void handle__ ( )
    {
    }
}

