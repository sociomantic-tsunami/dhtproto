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
