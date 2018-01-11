/*******************************************************************************

    Request protocol mixins.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.core.Mixins;

/*******************************************************************************

    Request core mixin.

*******************************************************************************/

public template RequestCore ( )
{
    import dhtproto.node.neo.request.core.IRequestResources;

    /***************************************************************************

        Shared resources getter instance.

    ***************************************************************************/

    protected IRequestResources resources;

    /***************************************************************************

        Constructor.

        Params:
            shared_resources = DHT request resources getter

    ***************************************************************************/

    public this ( IRequestResources resources )
    {
        this.resources = resources;
    }
}

/*******************************************************************************

    IRequestHandler-based request core mixin.

*******************************************************************************/

public template IRequestHandlerRequestCore ( )
{
    import swarm.neo.node.RequestOnConn;
    import dhtproto.node.neo.request.core.IRequestResources;

    /// Request-on-conn of this request handler.
    private RequestOnConn connection;

    /// Acquired resources of this request.
    private IRequestResources resources;

    /***************************************************************************

        Passes the request-on-conn and request resource acquirer to the handler.

        Params:
            connection = request-on-conn in which the request handler is called
            resources = request resources acquirer

    ***************************************************************************/

    public void initialise ( RequestOnConn connection, Object resources_object )
    {
        this.connection = connection;
        this.resources = cast(IRequestResources)resources_object;
        assert(this.resources !is null);
    }
}
