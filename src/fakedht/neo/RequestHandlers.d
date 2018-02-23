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

import GetHashRange = fakedht.neo.request.GetHashRange;
import fakedht.neo.request.Put;
import fakedht.neo.request.Get;
import fakedht.neo.request.Mirror;
import GetAll = fakedht.neo.request.GetAll;
import fakedht.neo.request.GetChannels;
import fakedht.neo.request.Exists;

/*******************************************************************************

    This table of request handlers by command is used by the connection handler.
    When creating a new request, the function corresponding to the request
    command is called in a fiber.

*******************************************************************************/

public ConnectionHandler.RequestMap requests;

static this ( )
{
    requests.add(RequestCode.GetHashRange, "GetHashRange", &GetHashRange.handle);
    requests.add(Command(RequestCode.Put, 0), "Put", PutImpl_v0.classinfo);
    requests.add(Command(RequestCode.Get, 0), "Get", GetImpl_v0.classinfo);
    requests.add(Command(RequestCode.Mirror, 0), "Mirror", MirrorImpl_v0.classinfo);
    requests.add(RequestCode.GetAll, "GetAll", &GetAll.handle);
    requests.add(Command(RequestCode.GetChannels, 0),
        "GetChannels", GetChannelsImpl_v0.classinfo);
    requests.add(Command(RequestCode.Exists, 0),
        "Exists", ExistsImpl_v0.classinfo);
}
