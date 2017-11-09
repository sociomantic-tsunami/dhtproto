/*******************************************************************************

    Turtle implementation of DHT `RemoveChannel` request

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.RemoveChannel;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import Protocol = dhtproto.node.request.RemoveChannel;

/*******************************************************************************

    Request implementation

*******************************************************************************/

public scope class RemoveChannel : Protocol.RemoveChannel
{
    import fakedht.mixins.RequestConstruction;
    import fakedht.Storage;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();

    /***************************************************************************

        Checks whether the specified channel is in active use by a listener.

        Params:
            channel_name = name of channel to be removed

        Returns:
            true if the channel is actively in use by a listener

    ***************************************************************************/

    override protected bool isChannelListened ( cstring channel_name )
    {
        if ( auto channel = global_storage.get(channel_name) )
            return channel.registered_listeners > 0;
        else
            return false;
    }

    /***************************************************************************

        Must remove the specified channel from the storage engine.
        Any failure is considered critical.

        Params:
            channel_name = name of channel to be removed

    ***************************************************************************/

    override protected void removeChannel ( cstring channel_name )
    {
        global_storage.remove(channel_name);
    }
}
