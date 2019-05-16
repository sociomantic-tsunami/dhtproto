/*******************************************************************************

    Table of request handlers by command.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.neo.RequestHandlers;

import swarm.neo.node.ConnectionHandler;
import swarm.neo.request.Command;

import dhtproto.common.RequestCodes;

import fakedht.neo.request.GetHashRange;
import fakedht.neo.request.Put;
import fakedht.neo.request.Get;
import fakedht.neo.request.Mirror;
import fakedht.neo.request.GetAll;
import fakedht.neo.request.Remove;
import fakedht.neo.request.GetChannels;
import fakedht.neo.request.Exists;
import fakedht.neo.request.RemoveChannel;
import fakedht.neo.request.Update;

/*******************************************************************************

    This table of request handlers by command is used by the connection handler.
    When creating a new request, the function corresponding to the request
    command is called in a fiber.

*******************************************************************************/

public ConnectionHandler.RequestMap requests;

static this ( )
{
    requests.addHandler!(GetHashRangeImpl_v0);
    requests.addHandler!(PutImpl_v0);
    requests.addHandler!(GetImpl_v0);
    requests.addHandler!(MirrorImpl_v0);
    requests.addHandler!(GetAllImpl_v0);
    requests.addHandler!(RemoveImpl_v0);
    requests.addHandler!(GetChannelsImpl_v0);
    requests.addHandler!(ExistsImpl_v0);
    requests.addHandler!(RemoveChannelImpl_v0);
    requests.addHandler!(UpdateImpl_v0);
}
