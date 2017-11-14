/*******************************************************************************

    Table of request handlers by command.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.neo.RequestHandlers;

import swarm.neo.node.ConnectionHandler;

import dhtproto.common.RequestCodes;

import GetHashRange = fakedht.neo.request.GetHashRange;
import Put = fakedht.neo.request.Put;
import Get = fakedht.neo.request.Get;
import Mirror = fakedht.neo.request.Mirror;
import GetAll = fakedht.neo.request.GetAll;
import GetChannels = fakedht.neo.request.GetChannels;
import Exists = fakedht.neo.request.Exists;

/*******************************************************************************

    This table of request handlers by command is used by the connection handler.
    When creating a new request, the function corresponding to the request
    command is called in a fiber.

*******************************************************************************/

public ConnectionHandler.RequestMap requests;

static this ( )
{
    requests.add(RequestCode.GetHashRange, "GetHashRange", &GetHashRange.handle);
    requests.add(RequestCode.Put, "Put", &Put.handle);
    requests.add(RequestCode.Get, "Get", &Get.handle);
    requests.add(RequestCode.Mirror, "Mirror", &Mirror.handle);
    requests.add(RequestCode.GetAll, "GetAll", &GetAll.handle);
    requests.add(RequestCode.GetChannels, "GetChannels", &GetChannels.handle);
    requests.add(RequestCode.Exists, "Exists", &Exists.handle);
}
