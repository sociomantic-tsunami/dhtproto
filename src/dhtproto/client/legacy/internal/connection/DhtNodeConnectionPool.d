/*******************************************************************************

    Pool of dht node socket connections holding IRequest instances

    Copyright:
        Copyright (c) 2011-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.connection.DhtNodeConnectionPool;



/*******************************************************************************

    Imports

*******************************************************************************/

import swarm.client.model.ClientSettings;

import swarm.client.connection.NodeConnectionPool;
import swarm.client.connection.RequestOverflow;

import dhtproto.client.legacy.internal.connection.model.IDhtNodeConnectionPoolInfo;

import dhtproto.client.legacy.DhtConst;
import Hash = swarm.util.Hash;

import dhtproto.client.legacy.internal.DhtClientExceptions;

import dhtproto.client.legacy.internal.connection.SharedResources;
import dhtproto.client.legacy.internal.connection.DhtRequestConnection;

import dhtproto.client.legacy.internal.request.params.RequestParams;

import dhtproto.client.legacy.internal.request.notifier.RequestNotification;

import dhtproto.client.legacy.internal.request.model.IRequest;

debug (SwarmClient) import ocean.io.Stdout;

import ocean.core.Enforce;
import ocean.core.Verify;

import ocean.math.Range;

import ocean.io.compress.lzo.LzoChunkCompressor;

import ocean.meta.types.Qualifiers;


/*******************************************************************************

    DhtNodeConnectionPool

    Provides a pool of dht node socket connections where each connection
    instance holds Reqest instances for the dht requests.

*******************************************************************************/

public class DhtNodeConnectionPool : NodeConnectionPool, IDhtNodeConnectionPoolInfo
{
    /***************************************************************************

        Shared resources instance.

    ***************************************************************************/

    private SharedResources shared_resources;


    /***************************************************************************

        Lzo chunk de/compressor used by this connection pool. Passed as a
        reference to the constructor.

    ***************************************************************************/

    private LzoChunkCompressor lzo;


    /***************************************************************************

        Exceptions thrown on error.

    ***************************************************************************/

    private VersionException version_exception;


    /***************************************************************************

        Flag set when the API version of the dht node this pool of connections
        is dealing with has been queried and matches the client's.

    ***************************************************************************/

    private bool version_ok;


    /***************************************************************************

        Flag set when the hash range supported by the dht node this pool of
        connections is dealing with has been queried.

    ***************************************************************************/

    private bool range_queried;


    /***************************************************************************

        Minimum and maximum hash of the dht node this pool of connections is
        dealing with.

    ***************************************************************************/

    private Hash.HashRange hash_range;


    /***************************************************************************

        Constructor

        Params:
            settings = client settings instance
            epoll = selector dispatcher instances to register the socket and I/O
                events
            address = node address
            port = node service port
            lzo = lzo chunk de/compressor
            request_overflow = overflow handler for requests which don't fit in
                the request queue
            shared_resources = shared resources instance
            error_reporter = error reporter instance to notify on error or
                timeout

    ***************************************************************************/

    public this ( ClientSettings settings, EpollSelectDispatcher epoll,
        mstring address, ushort port, LzoChunkCompressor lzo,
        IRequestOverflow request_overflow,
        SharedResources shared_resources,
        INodeConnectionPoolErrorReporter error_reporter )
    {
        this.shared_resources = shared_resources;

        this.lzo = lzo;

        this.version_exception = new VersionException;

        super(settings, epoll, address, port, request_overflow, error_reporter);
    }


    /***************************************************************************

        Creates a new instance of the connection request handler class.

        Returns:
            new DhtRequestConnection instance

    ***************************************************************************/

    override protected DhtRequestConnection newConnection ( )
    {
        return new DhtRequestConnection(this.epoll, this.lzo, this,
            this.newRequestParams(), this.fiber_stack_size,
            this.shared_resources);
    }


    /***************************************************************************

        Creates a new instance of the connection request params class.

        Returns:
            new RequestParams instance

    ***************************************************************************/

    override protected IRequestParams newRequestParams ( )
    {
        return new RequestParams;
    }


    /***************************************************************************

        Returns:
            true if the API version of the DHT node which the connections in
            this pool are connected to has been queried and matches the client's

     **************************************************************************/

    override public bool api_version_ok ( )
    {
        return this.version_ok;
    }


    /***************************************************************************

        Returns:
            true if the hash range of the DHT node which the connections in this
            pool are connected to has been set.

     **************************************************************************/

    override public bool hash_range_queried ( )
    {
        return this.range_queried;
    }


    /***************************************************************************

        Sets the hash range for the DHT node which the connections in this pool
        are connected to.

        Params:
            range = range of hash values handled by node

     **************************************************************************/

    public void setNodeRange ( hash_t min_hash, hash_t max_hash )
    {
        debug ( SwarmClient ) Stderr.formatln("setNodeRange: {}:{} -- 0x{:x}..0x{:x}",
            super.address, super.port, min_hash, max_hash);

        this.range_queried = true;
        this.hash_range = Hash.HashRange(min_hash, max_hash);
    }


    /***************************************************************************

        Checks the API version for the DHT node which the connections in this
        pool are connected to. The received API version must be the same as the
        version this client is compiled with.

        Params:
            api = API version reported by node

        Throws:
            VersionException if the node's API version does not match the
                client's

    ***************************************************************************/

    public void setAPIVerison ( cstring api )
    {
        debug ( SwarmClient ) Stderr.formatln("setAPIVersion: {}:{} -- {}",
            super.address, super.port, api);

        enforce(this.version_exception, api == DhtConst.ApiVersion);

        this.version_ok = true;
    }


    /***************************************************************************

        Returns:
            minimum hash of the dht node this pool of connections is dealing
            with

     **************************************************************************/

    override public hash_t min_hash ( )
    {
        return this.hash_range.min;
    }


    /***************************************************************************

        Returns:
            maximum hash of the dht node this pool of connections is dealing
            with

     **************************************************************************/

    override public hash_t max_hash ( )
    {
        return this.hash_range.max;
    }


    /***************************************************************************

        Tells whether the DHT node to which the connections in this pool are
        connected is responsible for key.

        Params:
            key = key to check responsibility for

        Returns:
            true if responsible or false otherwise

     **************************************************************************/

    public bool isResponsibleFor ( hash_t hash )
    {
        return this.range_queried
            ? Hash.isWithinNodeResponsibility(
                hash, this.hash_range.min, this.hash_range.max)
            : false;
    }


    /***************************************************************************

        Tells whether the DHT node to which the connections in this pool are
        connected is responsible for any keys in the given range.

        Params:
            start = start key to check responsibility for
            end = end key to check responsibility for

        Returns:
            true if responsible or false otherwise

     **************************************************************************/

    public bool coversRange ( hash_t start, hash_t end )
    {
        verify(this.range_queried, typeof(this).stringof ~ ".coversRange: node hash range unknown -- cannot query");
        return this.hash_range.overlaps(Hash.HashRange(start, end));
    }
}
