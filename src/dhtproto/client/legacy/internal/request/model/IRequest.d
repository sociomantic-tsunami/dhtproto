/*******************************************************************************

    Abstract base class for dht client requests.

    Copyright:
        Copyright (c) 2011-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.request.model.IRequest;



/*******************************************************************************

    Imports

*******************************************************************************/

import Core = swarm.client.request.model.IRequest;

import dhtproto.client.legacy.DhtConst;

import dhtproto.client.legacy.internal.request.params.RequestParams;

import dhtproto.client.legacy.internal.request.model.IDhtRequestResources;




/*******************************************************************************

    Dht client IRequest class

*******************************************************************************/

public scope class IRequest : Core.IRequest
{
    /***************************************************************************

        Aliases for the convenience of sub-classes, avoiding public imports.

    ***************************************************************************/

    protected alias .DhtConst DhtConst;

    protected alias .RequestParams RequestParams;

    protected alias .IDhtRequestResources IDhtRequestResources;


    /***************************************************************************

        Shared resources which might be required by the request.

    ***************************************************************************/

    protected IDhtRequestResources resources;


    /***************************************************************************

        Status code received from dht node.

    ***************************************************************************/

    protected DhtConst.Status.E status_ = DhtConst.Status.E.Undefined;


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
        super(reader, writer, resources.fatal_error_exception);

        this.resources = resources;
    }


    /***************************************************************************

        Returns:
            status received from dht node

    ***************************************************************************/

    public DhtConst.Status.E status ( )
    {
        return this.status_;
    }


    /***************************************************************************

        Sends the node any data required by the request.

        The base class only sends the command, and calls the abstract
        sendRequestData_(), which sub-classes must implement.

    ***************************************************************************/

    final override protected void sendRequestData ( )
    {
        this.writer.write(this.params.command);

        this.sendRequestData_();
    }

    abstract protected void sendRequestData_ ( );


    /***************************************************************************

        Receives the status code from the node.

    ***************************************************************************/

    override protected void receiveStatus ( )
    {
        this.reader.read(this.status_);
    }


    /***************************************************************************

        Decides which action to take after receiving a status code from the
        node.

        Returns:
            action enum value (handle request / skip request / kill connection)

    ***************************************************************************/

    override protected StatusAction statusAction ( )
    {
        if ( this.status_ in DhtConst.Status() )
        {
            with ( DhtConst.Status.E ) switch ( this.status_ )
            {
                case Ok:
                    return StatusAction.Handle;
                case Error:
                    return StatusAction.Fatal;
                default:
                    return StatusAction.Skip;
            }
        }
        else
        {
            return StatusAction.Fatal;
        }
    }


    /***************************************************************************

        Accessor method to cast from the abstract IRequestParams instance in the
        base class to the RequestParams class required by derived classes.

    ***************************************************************************/

    protected RequestParams params ( )
    {
        return cast(RequestParams)this.params_;
    }
}
