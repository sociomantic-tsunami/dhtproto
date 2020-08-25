/******************************************************************************

    Asynchronously/Selector managed DHT GetVersion request class

    Sends the received api version to the provided output delegate.

    Copyright:
        Copyright (c) 2011-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

******************************************************************************/

module dhtproto.client.legacy.internal.request.GetVersionRequest;



/******************************************************************************

    Imports

******************************************************************************/

import dhtproto.client.legacy.internal.request.model.IRequest;




/******************************************************************************

    GetVersionRequest class

******************************************************************************/

public class GetVersionRequest : IRequest
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
        this.reader.readArray(*this.resources.value_buffer);

        auto output = params.io_item.get_node_value();
        output(this.params.context, this.resources.conn_pool_info.address,
            this.resources.conn_pool_info.port, *this.resources.value_buffer);
    }
}

