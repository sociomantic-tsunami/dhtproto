/*******************************************************************************

    Interface and base scope class containing getter methods to acquire
    resources needed by a dht client request. Multiple calls to the same
    getter only result in the acquiring of a single resource of that type, so
    that the same resource is used over the life time of a request. When a
    request resource instance goes out of scope all required resources are
    automatically relinquished.

    Copyright:
        Copyright (c) 2012-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.request.model.IDhtRequestResources;



/*******************************************************************************

    Imports

*******************************************************************************/

import swarm.common.request.model.IRequestResources;

import dhtproto.client.legacy.internal.connection.SharedResources;

import swarm.client.connection.model.INodeConnectionPoolInfo;

import swarm.client.ClientExceptions :
    EmptyValueException, FatalErrorException;



/*******************************************************************************

    Mix in an interface called IRequestResources which contains a getter method
    for each type of acquirable resource, as defined by the SharedResources
    class (dhtproto.client.legacy.internal.connection.SharedResources).

*******************************************************************************/

mixin IRequestResources_T!(SharedResources);



/*******************************************************************************

    Interface which extends the base IRequestResources, adding some additional
    dht-specific getters.

*******************************************************************************/

public interface IDhtRequestResources : IRequestResources
{
    /***************************************************************************

        Local type re-definitions.

    ***************************************************************************/

    alias .FiberSelectEvent FiberSelectEvent;
    alias .LoopCeder LoopCeder;
    alias .RequestSuspender RequestSuspender;
    alias .FatalErrorException FatalErrorException;
    alias .EmptyValueException EmptyValueException;


    /***************************************************************************

        Connection pool info interface getter.

    ***************************************************************************/

    INodeConnectionPoolInfo conn_pool_info  ( );


    /***************************************************************************

        Fatal exception getter.

    ***************************************************************************/

    FatalErrorException fatal_error_exception ( );


    /***************************************************************************

        Empty value exception getter.

    ***************************************************************************/

    EmptyValueException empty_value_exception ( );
}



/*******************************************************************************

    Mix in a scope class called RequestResources which implements
    IRequestResources.

    Note that this class does not implement the additional methods required by
    IDhtRequestResources -- this is done in
    dhtproto.client.legacy.internal.connection.DhtRequestConnection.

*******************************************************************************/

mixin RequestResources_T!(SharedResources);

