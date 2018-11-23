/******************************************************************************

    Asynchronously/Selector managed DHT GetResponsibleRange request class

    Sends the received api version to the provided output delegate.

    Copyright:
        Copyright (c) 2011-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

******************************************************************************/

module dhtproto.client.legacy.internal.request.GetResponsibleRangeRequest;



/******************************************************************************

    Imports

******************************************************************************/

import dhtproto.client.legacy.internal.request.model.IRequest;

import dhtproto.client.legacy.DhtConst;

import swarm.util.Hash : HashRange;



/******************************************************************************

    GetResponsibleRangeRequest class

******************************************************************************/

public scope class GetResponsibleRangeRequest : IRequest
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
    }


    /***************************************************************************

        Handles a request once the request data has been sent and a valid status
        has been received from the node.

    ***************************************************************************/

    override protected void handle__ ( )
    {
        hash_t min, max;

        this.reader.read(min);
        this.reader.read(max);

        auto output = this.params.io_item.get_hash_range();
        output(this.params.context, this.resources.conn_pool_info.address,
            this.resources.conn_pool_info.port, HashRange(min, max));
    }
}

