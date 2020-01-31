/*******************************************************************************

    Fake DHT node GetChannels request implementation.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.neo.request.GetChannels;

import dhtproto.node.neo.request.GetChannels;

import fakedht.neo.SharedResources;
import swarm.neo.node.RequestOnConn;
import swarm.neo.request.Command;

import ocean.meta.types.Qualifiers;

/*******************************************************************************

    Fake node implementation of the v0 GetChannels request protocol.

*******************************************************************************/

public class GetChannelsImpl_v0 : GetChannelsProtocol_v0
{
    import fakedht.Storage;
    import dhtproto.common.RequestCodes : RequestCode;
    import ocean.text.convert.Hash : toHashT;

    /// Request code / version. Required by ConnectionHandler.
    static immutable Command command = Command(RequestCode.GetChannels, 0);

    /// Request name for stats tracking. Required by ConnectionHandler.
    static immutable istring name = "GetChannels";

    /// Flag indicating whether timing stats should be gathered for requests of
    /// this type.
    static immutable bool timing = false;

    /// Flag indicating whether this request type is scheduled for removal. (If
    /// true, clients will be warned.)
    static immutable bool scheduled_for_removal = false;

    /***************************************************************************

        opApply iteration over the names of the channels in storage.

    ***************************************************************************/

    override protected int opApply ( scope int delegate ( ref cstring ) dg )
    {
        int ret;
        foreach ( channel; global_storage.getChannelList() )
        {
            cstring const_channel = channel;
            ret = dg(const_channel);
            if ( ret )
                break;
        }
        return ret;
    }
}
