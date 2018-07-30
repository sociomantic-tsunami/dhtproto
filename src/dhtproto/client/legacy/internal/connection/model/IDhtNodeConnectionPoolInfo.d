/*******************************************************************************

    Information about a dht connection pool

    Copyright:
        Copyright (c) 2011-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.connection.model.IDhtNodeConnectionPoolInfo;



/*******************************************************************************

    Imports

*******************************************************************************/

import swarm.client.connection.model.INodeConnectionPoolInfo;



public interface IDhtNodeConnectionPoolInfo : INodeConnectionPoolInfo
{
    /***************************************************************************

        Returns:
            true if the API version for this pool has been queried and matches
            the client's

    ***************************************************************************/

    public bool api_version_ok ( );


    /***************************************************************************

        Returns:
            true if the hash range for this pool has been queried and set

    ***************************************************************************/

    public bool hash_range_queried ( );


    /***************************************************************************

        Returns:
            the minimum hash which this pool's node is responsible for

    ***************************************************************************/

    public hash_t min_hash ( );


    /***************************************************************************

        Returns:
            the maximum hash which this pool's node is responsible for

    ***************************************************************************/

    public hash_t max_hash ( );
}

