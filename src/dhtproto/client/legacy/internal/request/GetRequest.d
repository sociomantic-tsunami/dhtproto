/*******************************************************************************

    Asynchronously/Selector managed DHT Get request class

    Processes the dht node's output after a Get command, and forwards
    the received data to the provided output delegate.

    Copyright:
        Copyright (c) 2011-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.request.GetRequest;



/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.client.legacy.internal.request.model.IKeyRequest;




/*******************************************************************************

    GetRequest class

*******************************************************************************/

public scope class GetRequest : IKeyRequest
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

        Sends the node any data required by the request.

    ***************************************************************************/

    override protected void sendRequestData___ ( )
    {
    }


    /***************************************************************************

        Handles a request once the request data has been sent and a valid status
        has been received from the node.

    ***************************************************************************/

    override protected void handle__ ( )
    {
        if (!this.reader.readArrayLimit(*this.resources.value_buffer, MaximumRecordSize))
        {
            throw this.inputException.set(
                    "Error while reading the record's value: too large");
        }

        auto output = this.params.io_item.get_value();

        output(this.params.context, *this.resources.value_buffer);
    }
}

