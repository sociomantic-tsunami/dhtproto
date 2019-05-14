/*******************************************************************************

    Fake DHT node RemoveChannel request implementation.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.neo.request.RemoveChannel;

import dhtproto.node.neo.request.RemoveChannel;

import fakedht.neo.SharedResources;
import swarm.neo.node.RequestOnConn;
import swarm.neo.request.Command;

import ocean.transition;

/*******************************************************************************

    Fake node implementation of the v0 RemoveChannel request protocol.

*******************************************************************************/

public class RemoveChannelImpl_v0 : RemoveChannelProtocol_v0
{
    import fakedht.Storage;

    /***************************************************************************

        Checks whether the specified client is permitted to remove channels.

        Params:
            client_name = name of client requesting channel removal

        Returns:
            true if the client is permitted to remove channels

    ***************************************************************************/

    override protected bool clientPermitted ( cstring client_name )
    {
        // In tests, always allow channel removal.
        return true;
    }

    /***************************************************************************

        Removes the specified channel.

        Params:
            channel_name = channel to remove

        Returns:
            true if the operation succeeded (the channel was removed or did not
            exist); false if an error occurred

    ***************************************************************************/

    override protected bool removeChannel ( cstring channel_name )
    {
        global_storage.remove(channel_name);
        return true;
    }
}
