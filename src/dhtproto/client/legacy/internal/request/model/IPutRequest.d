/*******************************************************************************

    Base class for asynchronously/Selector managed DHT Put requests

    Copyright:
        Copyright (c) 2010-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.request.model.IPutRequest;



/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.client.legacy.internal.request.model.IKeyRequest;

import dhtproto.client.legacy.DhtConst;

import dhtproto.client.legacy.internal.request.params.RequestParams;

import swarm.client.ClientExceptions;

import ocean.core.Enforce;

import ocean.meta.types.Qualifiers;


/*******************************************************************************

    IPutRequest abstract class

*******************************************************************************/

public class IPutRequest : IKeyRequest
{
    /***************************************************************************

        Constructor.

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

        The base class only sends the value (the command, channel and key have
        been written by the super classes). The value is retrieved by calling
        the abstract getValue(), which sub-classes must implement.

    ***************************************************************************/

    final override protected void sendRequestData___ ( )
    {
        auto value = this.getValue();
        enforce(this.resources.empty_value_exception, value.length);

        this.writer.writeArray(value);
    }


    /***************************************************************************

        Returns:
            value to put

    ***************************************************************************/

    abstract protected cstring getValue ( );
}

