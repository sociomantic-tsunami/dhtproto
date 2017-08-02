/*******************************************************************************

    Asynchronously/Selector managed DHT Exists request class

    Processes the dht node's output after a Exists command, and forwards
    the received data to the provided output delegate.

    Copyright:
        Copyright (c) 2011-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.request.ExistsRequest;



/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.client.legacy.internal.request.model.IKeyRequest;




/*******************************************************************************

    ExistsRequest class

*******************************************************************************/

public scope class ExistsRequest : IKeyRequest
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
        assert(this.params.io_item.active == this.params.io_item.Active.get_bool, typeof(this).stringof ~ ".handle: I/O delegate mismatch");
        bool exists;
        this.reader.read(exists);

        auto output = this.params.io_item.get_bool();

        output(this.params.context, exists);
    }
}

