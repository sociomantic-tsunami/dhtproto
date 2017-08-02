/*******************************************************************************

    Asynchronously/Selector managed DHT Put request class

    Reads the value to be written from the provided input delegate.

    Copyright:
        Copyright (c) 2011-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.request.PutRequest;



/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.client.legacy.internal.request.model.IPutRequest;

import ocean.transition;


/*******************************************************************************

    PutRequest class

*******************************************************************************/

public scope class PutRequest : IPutRequest
{
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
            the value to be written to the node

    ***************************************************************************/

    override protected cstring getValue ( )
    {
        auto input = params.io_item.put_value();

        return input(this.params.context);
    }


    /***************************************************************************

        Handles a request once the request data has been sent and a valid status
        has been received from the node.

    ***************************************************************************/

    override protected void handle__ ( )
    {
    }
}

