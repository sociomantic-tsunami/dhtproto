/*******************************************************************************

    DHT node connection registry

    Copyright:
        Copyright (c) 2010-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.registry.DhtNodeRegistry;



/******************************************************************************

    Imports

*******************************************************************************/

import swarm.client.ClientCommandParams;

import swarm.client.registry.NodeRegistry;
import swarm.client.registry.NodeSet;

import swarm.client.connection.RequestOverflow;
import dhtproto.client.legacy.internal.connection.SharedResources;

import dhtproto.client.legacy.internal.connection.model.IDhtNodeConnectionPoolInfo;

import dhtproto.client.legacy.internal.registry.model.IDhtNodeRegistryInfo;

import dhtproto.client.legacy.internal.connection.DhtRequestConnection,
               dhtproto.client.legacy.internal.connection.DhtNodeConnectionPool;

import dhtproto.client.legacy.internal.request.params.RequestParams;

import swarm.client.request.context.RequestContext;

import dhtproto.client.legacy.DhtConst;

import dhtproto.client.legacy.internal.DhtClientExceptions;

import ocean.transition;

import ocean.io.select.EpollSelectDispatcher;

import ocean.core.Enforce;
import ocean.core.Verify;

import ocean.io.compress.lzo.LzoChunkCompressor;

debug ( SwarmClient ) import ocean.io.Stdout;



/******************************************************************************

    DhtNodeRegistry

    Registry of DHT node socket connections pools with one connection pool for
    each DHT node.

*******************************************************************************/

public class DhtNodeRegistry : NodeRegistry, IDhtNodeRegistryInfo
{
    /***************************************************************************

        Number of expected nodes in the registry. Used to initialise the
        registry's hash map.

    ***************************************************************************/

    private static immutable expected_nodes = 100;


    /***************************************************************************

        Shared resources instance. Owned by this class and passed to all node
        connection pools.

    ***************************************************************************/

    private SharedResources shared_resources;


    /***************************************************************************

        Lzo chunk de/compressor shared by all connections and request handlers.

    ***************************************************************************/

    protected LzoChunkCompressor lzo;


    /***************************************************************************

        Exceptions thrown on error.

    ***************************************************************************/

    private VersionException version_exception;

    private NodeOverlapException node_overlap_exception;

    private RegistryLockedException registry_locked_exception;


    /***************************************************************************

        Constructor

        Params:
            epoll = selector dispatcher instance to register the socket and I/O
                events
            settings = client settings instance
            request_overflow = overflow handler for requests which don't fit in
                the request queue
            error_reporter = error reporter instance to notify on error or
                timeout

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll, ClientSettings settings,
        IRequestOverflow request_overflow,
        INodeConnectionPoolErrorReporter error_reporter )
    {
        super(epoll, settings, request_overflow,
            new NodeSet(this.expected_nodes, &this.modified), error_reporter);

        this.version_exception = new VersionException;
        this.node_overlap_exception = new NodeOverlapException;
        this.registry_locked_exception = new RegistryLockedException;

        this.shared_resources = new SharedResources;

        this.lzo = new LzoChunkCompressor;
    }


    /***************************************************************************

        Creates a new instance of the dht node request pool class.

        Params:
            address = node address
            port = node service port

        Returns:
            new NodeConnectionPool instance

    ***************************************************************************/

    override protected NodeConnectionPool newConnectionPool ( mstring address, ushort port )
    {
        return new DhtNodeConnectionPool(this.settings, this.epoll,
            address, port, this.lzo, this.request_overflow,
            this.shared_resources, this.error_reporter);
    }


    /***************************************************************************

        Gets the connection pool which is responsible for the given request.

        Params:
            params = request parameters

        Returns:
            connection pool responsible for request (null if none found)

    ***************************************************************************/

    override protected NodeConnectionPool getResponsiblePool ( IRequestParams params )
    {
        if ( params.node.set() )
        {
            auto pool = super.inRegistry(params.node.Address, params.node.Port);
            return pool is null ? null : *pool;
        }

        auto dht_params = cast(RequestParams)params;
        return this.getResponsiblePool_(dht_params.hash);
    }


    /***************************************************************************

        Gets an informational interface to the connection pool which is
        responsible for the given hash.

        Params:
            hash = hash to get responsible connection pool for

        Returns:
            informational interface to connection pool responsible for hash
            (null if none found)

    ***************************************************************************/

    override public IDhtNodeConnectionPoolInfo responsibleNode ( hash_t hash )
    {
        return this.getResponsiblePool_(hash);
    }


    /***************************************************************************

        Determines whether the given request params describe a request which
        should be sent to all nodes simultaneously.

        Multi-node requests which have not been assigned with a particular node
        specified are sent to all nodes.

        Params:
            params = request parameters

        Returns:
            true if the request should be added to all nodes

    ***************************************************************************/

    override public bool allNodesRequest ( IRequestParams params )
    {
        with ( DhtConst.Command.E ) switch ( params.command )
        {
            // Commands over all nodes
            case GetAll:
            case GetAllFilter:
            case GetAllKeys:
            case GetChannels:
            case GetSize:
            case GetResponsibleRange:
            case GetChannelSize:
            case RemoveChannel:
            case GetNumConnections:
            case GetVersion:
            case Listen:
                return !params.node.set();

            // Commands over a single node
            case Put:
            case Get:
            case Exists:
            case Remove:
                return false;

            // Commands over a single node which must be explicitly specified
            // (cannot be inferred from a key, for example)
            case Redistribute:
            case PutBatch:
                verify(params.node.set());
                return false;

            default:
                assert(false, typeof(this).stringof ~ ".allNodesRequest: invalid request");
        }
    }


    /***************************************************************************

        Adds a request to the individual node specified. If the request being
        assigned is not GetVersion or GetResponsibleRange*, then the node's API
        version is checked before assigning and an exception thrown if it is
        either unknown or does not match the client's.

        *GetResponsibleRange requests are allowed to execute without the API
        version being known as a concession to the current handshake procedure.
        Ideally, the API version should always be fetched first, followed by the
        hash range, then other requests. The current handshake, however, assigns
        GetVersion and GetResponsibleRange in parallel, so there's no way of
        enforcing this ordering. The handshake will hopefully be completely
        reworked at some point, when we can fix this issue. It seems like it's
        currently not worth putting in the effort to hack the current system to
        fix this minor technicality.

        Params:
            params = request parameters
            node_conn_pool = node connection pool to assign request to

        Throws:
            if the request is not GetVersion or GetResponsibleRange and the
            node's API version is not ok -- handled by the caller
            (assignToNode(), in the super class)

    ***************************************************************************/

    override protected void assignToNode_ ( IRequestParams params,
        NodeConnectionPool node_conn_pool )
    {
        auto dht_conn_pool = (cast(DhtNodeConnectionPool)node_conn_pool);
        verify(dht_conn_pool !is null);

        if ( params.command != DhtConst.Command.E.GetVersion &&
            params.command != DhtConst.Command.E.GetResponsibleRange )
        {
            enforce(this.version_exception, dht_conn_pool.api_version_ok);
        }

        super.assignToNode_(params, node_conn_pool);
    }


    /***************************************************************************

        Checks the API version for a node. The received API version must be the
        same as the version this client is compiled with.

        Params:
            address = address of node to set hash range for
            port = port of node to set hash range for
            api = API version reported by node

        Throws:
            - Exception if the specified node is not in the registry
            - VersionException if the node's API version does not match the
              client's

    ***************************************************************************/

    public void setNodeAPIVersion ( mstring address, ushort port, cstring api )
    {
        auto conn_pool = super.inRegistry(address, port);
        enforce(conn_pool, "node not in registry");

        auto dht_conn_pool = (cast(DhtNodeConnectionPool*)conn_pool);
        dht_conn_pool.setAPIVerison(api);
    }


    /***************************************************************************

        Sets the hash range for which a node is responsible and checks that no
        other node is also responsible for part of that range.

        Params:
            address = address of node to set hash range for
            port = port of node to set hash range for
            min = minimum hash the specified node should handle
            max = maximum hash the specified node should handle

        Throws:
            - Exception if the specified node is not in the registry
            - NodeOverlapException if another node in the registry is already
              known to be responsible for part of the specified hash range

    ***************************************************************************/

    public void setNodeResponsibleRange ( mstring address, ushort port,
        hash_t min, hash_t max )
    {
        auto conn_pool = super.inRegistry(address, port);
        enforce(conn_pool, "node not in registry");

        auto dht_conn_pool = (cast(DhtNodeConnectionPool*)conn_pool);
        dht_conn_pool.setNodeRange(min, max);

        foreach ( i, cp; this )
        {
            if ( cp is *conn_pool )
            {
                enforce(this.node_overlap_exception, cp.coversRange(min, max));
            }
            else
            {
                enforce(this.node_overlap_exception,
                    !cp.hash_range_queried || !cp.coversRange(min, max));
            }
        }
    }


    /***************************************************************************

        Tells if the client is ready to send requests to all nodes in the
        registry (i.e. they have all responded successfully to the handshake).

        Returns:
            true if all node API versions and hash ranges are known and there is
            no range gap or overlap. false otherwise.

    ***************************************************************************/

    public bool all_nodes_ok ( )
    {
        auto succeeded = this.all_node_ranges_known && !this.node_range_gap &&
            !this.node_range_overlap && this.all_versions_ok;

        debug ( SwarmClient ) Stderr.formatln("DhtNodeRegistry.all_nodes_ok={} " ~
            "(all_node_ranges_known={}, node_range_gap={}, " ~
            "node_range_overlap={}, all_versions_ok={})", succeeded,
            this.all_node_ranges_known, this.node_range_gap,
            this.node_range_overlap, this.all_versions_ok);

        return succeeded;
    }


    /**************************************************************************

        foreach iterator over connection pool info interfaces.

    **************************************************************************/

    public int opApply ( scope int delegate ( ref IDhtNodeConnectionPoolInfo ) dg )
    {
        int ret;

        foreach ( DhtNodeConnectionPool connpool; this )
        {
            auto info = cast(IDhtNodeConnectionPoolInfo)connpool;
            ret = dg(info);

            if ( ret ) break;
        }

        return ret;
    }


    /***************************************************************************

        Called when the registry is modified (by add(), for example).

        In the dht client, this method should only be called before the
        handshake.

        Throws:
            exception if the registry is locked

    ***************************************************************************/

    protected void modified ( )
    {
        enforce(this.registry_locked_exception, !this.all_node_ranges_known);
    }


    /***************************************************************************

        Returns:
            true if all node hash ranges are known or false if there are nodes
            in the registry whose node hash ranges are currently unknown.

    ***************************************************************************/

    override public bool all_node_ranges_known ( )
    {
        foreach ( DhtNodeConnectionPool connpool; this )
        {
            if ( !connpool.hash_range_queried ) return false;
        }

        return true;
    }


    /***************************************************************************

        Returns:
            true if all nodes support the correct API version or false if there
            are nodes in the registry whose API version is currently unknown or
            mismatched.

    ***************************************************************************/

    override public bool all_versions_ok ( )
    {
        foreach ( DhtNodeConnectionPool connpool; this )
        {
            if ( !connpool.api_version_ok ) return false;
        }

        return true;
    }


    /***************************************************************************

        Checks for gaps in the hash range covered by all dht nodes in the
        registry, ensuring that all possible hashes are handled by one of the
        nodes.

        The method does not check whether all node ranges are currently known.

        The method works by checking that each node's start hash is either
        0x00000000 or is one greater than another node's end hash, and that each
        node's end hash is either 0xffffffff or is one less than another node's
        start hash.

        Returns:
            true if any gaps are found or false if no gap was found

    ***************************************************************************/

    override public bool node_range_gap ( )
    {
        foreach ( DhtNodeConnectionPool connpool; this )
        {
            if ( !this.hashTouchesRangeEnd(connpool.min_hash) )
            {
                return true;
            }

            if ( !this.hashTouchesRangeStart(connpool.max_hash) )
            {
                return true;
            }
        }

        return false;
    }


    /***************************************************************************

        Checks for overlaps in the hash range covered by all dht nodes in the
        registry, ensuring that no hashes are handled by more than one of the
        nodes.

        The method does not check whether all node ranges are currently known.

        Returns:
            true if any overlaps are found or false if no overlap was found

    ***************************************************************************/

    override public bool node_range_overlap ( )
    {
        foreach ( DhtNodeConnectionPool connpool1; this )
        {
            foreach ( DhtNodeConnectionPool connpool2; this )
             {
                 if ( connpool1 != connpool2 )
                 {
                     if ( connpool1.coversRange(connpool2.min_hash, connpool2.max_hash) )
                     {
                         return true;
                     }
                 }
             }
        }

        return false;
    }


    /***************************************************************************

        Gets the connection pool which is responsible for the given hash. This
        logic is separated from the main getResponsiblePool() method as it is
        called from multiple locations.

        Params:
            hash = hash to get responsible connection pool for

        Returns:
            connection pool responsible for hash (null if none found)

    ***************************************************************************/

    private DhtNodeConnectionPool getResponsiblePool_ ( hash_t hash )
    {
        foreach ( i, connpool; this )
        {
            if ( connpool.isResponsibleFor(hash) )
            {
                enforce(this.version_exception, connpool.api_version_ok);

                return connpool;
            }
        }

        return null;
    }


    /***************************************************************************

        foreach iterator over the connection pools in the registry.

    ***************************************************************************/

    private int opApply ( scope int delegate ( ref DhtNodeConnectionPool ) dg )
    {
        int res;
        foreach ( pool; this.nodes.list )
        {
            auto dht_pool = cast(DhtNodeConnectionPool)pool;
            res = dg(dht_pool);

            if ( res ) break;
        }

        return res;
    }


    /***************************************************************************

        foreach iterator over the connection pools in the registry along with
        their indices in the list of connection pools.

    ***************************************************************************/

    private int opApply ( scope int delegate ( ref size_t, ref DhtNodeConnectionPool ) dg )
    {
        int res;
        size_t i;
        foreach ( nodeitem, pool; this.nodes.list )
        {
            auto dht_pool = cast(DhtNodeConnectionPool)pool;
            res = dg(i, dht_pool);
            i++;

            if ( res ) break;
        }

        return res;
    }


    /***************************************************************************

        Checks whether the given hash touches (ie is one greather than) the
        start of a dht node's range.

        Params:
            hash = hash to check

        Returns:
            true if the given hash is either 0x00000000 or is one greater than a
            dht node's end hash.

    ***************************************************************************/

    private bool hashTouchesRangeStart ( hash_t hash )
    {
        if ( hash == hash_t.max )
        {
            return true;
        }

        foreach ( DhtNodeConnectionPool connpool; this )
        {
            if ( hash == connpool.min_hash - 1 )
            {
                return true;
            }
        }

        return false;
    }


    /***************************************************************************

        Checks whether the given hash touches (ie is one less than) the end of a
        dht node's range.

        Params:
            hash = hash to check

        Returns:
            true if the given hash is either 0xffffffff or is one less than a
            dht node's start hash.

    ***************************************************************************/

    private bool hashTouchesRangeEnd ( hash_t hash )
    {
        if ( hash == hash_t.min )
        {
            return true;
        }

        foreach ( DhtNodeConnectionPool connpool; this )
        {
            if ( hash == connpool.max_hash + 1 )
            {
                return true;
            }
        }

        return false;
    }
}
