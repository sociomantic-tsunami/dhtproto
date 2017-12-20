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

import ocean.transition;

/*******************************************************************************

    The request handler for the table of handlers. When called, runs in a fiber
    that can be controlled via `connection`.

    Params:
        shared_resources = an opaque object containing resources owned by the
            node which are required by the request
        connection  = performs connection socket I/O and manages the fiber
        cmdver      = the version number of the Consume command as specified by
                      the client
        msg_payload = the payload of the first message of this request

*******************************************************************************/

public void handle ( Object shared_resources, RequestOnConn connection,
    Command.Version cmdver, Const!(void)[] msg_payload )
{
    auto resources = new SharedResources;

    switch ( cmdver )
    {
        case 0:
            scope rq = new GetChannelsImpl_v0(resources);
            rq.handle(connection, msg_payload);
            break;

        default:
            auto ed = connection.event_dispatcher;
            ed.send(
                ( ed.Payload payload )
                {
                    payload.addConstant(SupportedStatus.RequestVersionNotSupported);
                }
            );
            break;
    }
}

/*******************************************************************************

    Fake node implementation of the v0 GetChannels request protocol.

*******************************************************************************/

private scope class GetChannelsImpl_v0 : GetChannelsProtocol_v0
{
    import fakedht.Storage;
    import ocean.text.convert.Hash : toHashT;

    /***************************************************************************

        Constructor.

        Params:
            shared_resources = DHT request resources getter

    ***************************************************************************/

    public this ( IRequestResources resources )
    {
        super(resources);
    }

    /***************************************************************************

        opApply iteration over the names of the channels in storage.

    ***************************************************************************/

    override protected int opApply ( int delegate ( ref cstring ) dg )
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
