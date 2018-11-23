/*******************************************************************************

    I/O delegates of dht client requests, providing feedback between the dht
    client and the user.

    Copyright:
        Copyright (c) 2012-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.request.params.IODelegates;



/*******************************************************************************

    Imports

*******************************************************************************/

import swarm.client.request.context.RequestContext;

import swarm.client.request.model.ISuspendableRequest;
import swarm.client.request.model.IStreamInfo;

import swarm.Const;
import swarm.util.Hash : HashRange;

import dhtproto.client.legacy.DhtConst;

import dhtproto.client.legacy.common.NodeRecordBatcher;

import dhtproto.client.legacy.internal.request.params.RedistributeInfo;

import ocean.transition;


/*******************************************************************************

    Aliases for the IO delegates.

    N.B. it is important that the context is
    passed to all the delegates, as the users heavily rely on the request
    context inside the delegates.

*******************************************************************************/


/*******************************************************************************

   Alias for delegate which puts single values

*******************************************************************************/

public alias Const!(char[]) delegate (RequestContext) PutValueDg;


/*******************************************************************************

   Alias for delegate which puts compressed batches of values

*******************************************************************************/

public alias NodeRecordBatcher delegate (RequestContext) PutBatchDg;


/*******************************************************************************

   Alias for delegate for Redistribute request

*******************************************************************************/

public alias RedistributeInfo delegate (RequestContext) RedistributeDg;


/*******************************************************************************

    Alias for delegate which gets single values

*******************************************************************************/

public alias void delegate (RequestContext, Const!(char[])) GetValueDg;


/*******************************************************************************

    Alias for delegate which gets pairs of values

*******************************************************************************/

public alias void delegate (RequestContext, Const!(char[]), Const!(char[])) GetPairDg;


/*******************************************************************************

    Alias for delegate which gets single bools

*******************************************************************************/

public alias void delegate (RequestContext, bool) GetBoolDg;


/*******************************************************************************

    Alias for delegate which gets a DHT key range

*******************************************************************************/

public alias void delegate (RequestContext, Const!(char[]), ushort, HashRange) GetResponsibleRangeDg;


/*******************************************************************************

    Alias for delegate which gets a node's number of active connections (as
    returned by GetNumConnections)

*******************************************************************************/

public alias void delegate (RequestContext, Const!(char[]), ushort, size_t) GetNumConnectionsDg;


/*******************************************************************************

    Alias for delegate which gets a node's value (used to get the API
    version number and channel list).

*******************************************************************************/

public alias void delegate (RequestContext, Const!(char[]), ushort, Const!(char[])) GetNodeValueDg;


/*******************************************************************************

    Alias for delegate which gets a node's size info (as returned by
    GetSize)

*******************************************************************************/

public alias void delegate (RequestContext, Const!(char[]), ushort, ulong, ulong) GetSizeInfoDg;


/*******************************************************************************

    Alias for delegate which gets a node's size info (as returned by
    GetChannelSize)

*******************************************************************************/

public alias void delegate (RequestContext, Const!(char[]), ushort, Const!(char[]), ulong, ulong) GetChannelSizeInfoDg;


/*******************************************************************************

    Alias for delegate which gets an ISuspendable interface for a request

*******************************************************************************/

public alias void delegate (RequestContext, ISuspendableRequest) RegisterSuspendableDg;


/*******************************************************************************

    Alias for delegate which gets an IStreamInfo interface for a request

*******************************************************************************/

public alias void delegate (RequestContext, IStreamInfo) RegisterStreamInfoDg;
