/******************************************************************************

    Asynchronously/Selector managed DHT GetAllKeys request class

    Sends the received keys to the provided output delegate.

    Copyright:
        Copyright (c) 2011-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

******************************************************************************/

module dhtproto.client.legacy.internal.request.GetAllKeysRequest;



/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.client.legacy.internal.request.model.IBulkGetRequest;

import ocean.io.select.client.FiberSelectEvent;




/*******************************************************************************

    GetAllKeysRequest class

*******************************************************************************/

public scope class GetAllKeysRequest : IBulkGetValuesRequest
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

    override protected void sendRequestData__ ( )
    {
    }


    /***************************************************************************

        Processes a received key.

        Params:
            key = record key

    ***************************************************************************/

    override protected void processValue ( in char[] key )
    {
        auto output = this.params.io_item.get_value();

        output(this.params.context, key);
    }
}
