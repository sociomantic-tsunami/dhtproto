/******************************************************************************

    Interface defining public / external methods on a dht client's node
    registry. Instances of this interface can be safely exposed externally to
    the dht client.

    Copyright:
        Copyright (c) 2010-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.registry.model.IDhtNodeRegistryInfo;



/*******************************************************************************

    Imports

*******************************************************************************/

import dhtproto.client.legacy.DhtConst;

import swarm.client.registry.model.INodeRegistryInfo;

import dhtproto.client.legacy.internal.connection.model.IDhtNodeConnectionPoolInfo;



/*******************************************************************************

    Dht connection registry interface

*******************************************************************************/

public interface IDhtNodeRegistryInfo : INodeRegistryInfo
{
    /**************************************************************************

        Tells if the client is ready to send requests to all nodes in the
        registry (i.e. they have all responded successfully to the handshake).

        all_nodes_ok is defined in terms of the subsequent methods, as follows:
            all_node_ranges_known &&
            !node_range_gap &&
            !node_range_overlap &&
            all_versions_ok

        (FIXME_IN_D2: this method could be implemented (non-abstract) in this
        interface.)

        Returns:
            true if all node API versions and hash ranges are known and there is
            no range gap or overlap. false otherwise.

     **************************************************************************/

    public bool all_nodes_ok ( );


    /***************************************************************************

        Returns:
            true if all node hash ranges are known or false if there are nodes
            in the registry whose node hash ranges are currently unknown.

    ***************************************************************************/

    public bool all_node_ranges_known ( );


    /***************************************************************************

        Returns:
            true if all nodes support the correct API version or false if there
            are nodes in the registry whose API version is currently unknown or
            mismatched.

    ***************************************************************************/

    public bool all_versions_ok ( );


    /***************************************************************************

        Checks for gaps in the hash range covered by all dht nodes in the
        registry, ensuring that all possible hashes are handled by one of the
        nodes.

        The method does not check whether all node ranges are currently known.

        Returns:
            true if any gaps are found or false if no gap was found

    ***************************************************************************/

    public bool node_range_gap ( );


    /***************************************************************************

        Checks for overlaps in the hash range covered by all dht nodes in the
        registry, ensuring that no hashes are handled by more than one of the
        nodes.

        The method does not check whether all node ranges are currently known.

        Returns:
            true if any overlaps are found or false if no overlap was found

    ***************************************************************************/

    public bool node_range_overlap ( );


    /**************************************************************************

        foreach iterator over connection pool info interfaces.

    **************************************************************************/

    public int opApply ( scope int delegate ( ref IDhtNodeConnectionPoolInfo ) dg );


    /***************************************************************************

        Gets an informational interface to the connection pool which is
        responsible for the given hash.

        Params:
            hash = hash to get responsible connection pool for

        Returns:
            informational interface to connection pool responsible for hash
            (null if none found)

    ***************************************************************************/

    public IDhtNodeConnectionPoolInfo responsibleNode ( hash_t hash );
}

