/*******************************************************************************

    DHT node socket connection holding Request instances

    Copyright:
        Copyright (c) 2010-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.connection.DhtRequestConnection;



/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;
import ocean.core.Enforce;

import swarm.client.connection.RequestConnection;

import swarm.client.ClientExceptions
    : EmptyValueException, FatalErrorException;

import swarm.client.connection.model.INodeConnectionPool;

import dhtproto.client.legacy.internal.connection.SharedResources;

import dhtproto.client.legacy.internal.request.params.RequestParams;

import dhtproto.client.legacy.internal.request.notifier.RequestNotification;

import dhtproto.client.legacy.internal.request.model.IRequest;
import dhtproto.client.legacy.internal.request.model.IChannelRequest;

import dhtproto.client.legacy.internal.request.model.IDhtRequestResources;

import swarm.client.request.GetChannelsRequest;
import swarm.client.request.GetNumConnectionsRequest;
import swarm.client.request.GetChannelSizeRequest;
import swarm.client.request.GetSizeRequest;
import swarm.client.request.RemoveChannelRequest;

import swarm.util.RecordBatcher;

import dhtproto.client.legacy.internal.request.model.IDhtRequestResources;
import dhtproto.client.legacy.internal.request.GetVersionRequest;
import dhtproto.client.legacy.internal.request.GetResponsibleRangeRequest;
import dhtproto.client.legacy.internal.request.GetRequest;
import dhtproto.client.legacy.internal.request.GetAllRequest;
import dhtproto.client.legacy.internal.request.GetAllFilterRequest;
import dhtproto.client.legacy.internal.request.GetAllKeysRequest;
import dhtproto.client.legacy.internal.request.ListenRequest;
import dhtproto.client.legacy.internal.request.ExistsRequest;
import dhtproto.client.legacy.internal.request.RemoveRequest;
import dhtproto.client.legacy.internal.request.PutRequest;
import dhtproto.client.legacy.internal.request.PutBatchRequest;
import dhtproto.client.legacy.internal.request.RedistributeRequest;

import dhtproto.client.legacy.DhtConst;



/*******************************************************************************

    Request classes derived from templates in core

*******************************************************************************/

private alias GetChannelsRequestTemplate!(IRequest,
    IDhtRequestResources, DhtConst.Command.E.GetChannels)
    GetChannelsRequest;

private alias GetNumConnectionsRequestTemplate!(IRequest,
    IDhtRequestResources, DhtConst.Command.E.GetNumConnections)
    GetNumConnectionsRequest;

private alias GetChannelSizeRequestTemplate!(IChannelRequest,
    IDhtRequestResources, DhtConst.Command.E.GetChannelSize)
    GetChannelSizeRequest;

private alias GetSizeRequestTemplate!(IRequest,
    IDhtRequestResources, DhtConst.Command.E.GetSize)
    GetSizeRequest;

private alias RemoveChannelRequestTemplate!(IChannelRequest,
    IDhtRequestResources, DhtConst.Command.E.RemoveChannel)
    RemoveChannelRequest;



/******************************************************************************

    DhtRequestConnection

    Provides a DHT node socket connection and Reqest instances for the DHT
    requests.

*******************************************************************************/

public class DhtRequestConnection :
    RequestConnectionTemplate!(DhtConst.Command)
{
    /***************************************************************************

        Helper class to acquire and relinquish resources required by a request
        while it is handled. The resources are acquired from the shared
        resources instance which is passed to DhtRequestConnection's
        constructor. Acquired resources are automatically relinquished in the
        destructor.

        Note that it is assumed that each request will own at most one of each
        resource type (it is not possible, for example, to acquire two value
        buffers).

    ***************************************************************************/

    private scope class DhtRequestResources
        : RequestResources, IDhtRequestResources
    {
        import swarm.Const : NodeItem;


        /***********************************************************************

            Constructor.

        ***********************************************************************/

        public this ( )
        {
            super(this.outer.shared_resources);
        }


        /***********************************************************************

            Connection pool info getter.

        ***********************************************************************/

        public INodeConnectionPoolInfo conn_pool_info  ( )
        {
            return this.outer.conn_pool;
        }


        /***********************************************************************

            Invalid status exception getter.

        ***********************************************************************/

        public FatalErrorException fatal_error_exception ( )
        {
            return this.outer.fatal_error_exception;
        }


        /***********************************************************************

            Empty value exception getter.

        ***********************************************************************/

        public EmptyValueException empty_value_exception ( )
        {
            return this.outer.empty_value_exception;
        }


        /***********************************************************************

            Channel buffer newer.

        ***********************************************************************/

        override protected mstring new_channel_buffer ( )
        {
            return new char[10];
        }


        /***********************************************************************

            Key buffer newer.

        ***********************************************************************/

        override protected mstring new_key_buffer ( )
        {
            return new char[size_t.sizeof * 2];
        }


        /***********************************************************************

            Value buffer newer.

        ***********************************************************************/

        override protected mstring new_value_buffer ( )
        {
            return new char[50];
        }


        /***********************************************************************

            Address buffer newer.

        ***********************************************************************/

        override protected mstring new_address_buffer ( )
        {
            return new char[15]; // e.g. 255.255.255.255
        }


        /***********************************************************************

            Batch newer.

        ***********************************************************************/

        override protected mstring new_batch_buffer ( )
        {
            return new char[RecordBatcher.DefaultMaxBatchSize];
        }


        /***********************************************************************

            Codes list newer.

        ***********************************************************************/

        override protected DhtConst.Command.Value[] new_codes_list ( )
        {
            return new DhtConst.Command.Value[20];
        }


        /***********************************************************************

            Select event newer.

        ***********************************************************************/

        override protected FiberSelectEvent new_event ( )
        {
            return new FiberSelectEvent(this.outer.fiber);
        }


        /***********************************************************************

            Loop ceder newer.

        ***********************************************************************/

        override protected LoopCeder new_loop_ceder ( )
        {
            return new LoopCeder(this.event);
        }


        /***********************************************************************

            Request suspender newer.

        ***********************************************************************/

        override protected RequestSuspender new_request_suspender ( )
        {
            return new RequestSuspender(this.event,
                NodeItem(this.outer.conn_pool.address, this.outer.conn_pool.port),
                this.outer.params.context);
        }


        /***********************************************************************

            Record batch newer. Note that the lzo instance is owned by the
            node registry, and shared between all connections. Thus an init_()
            method is not required for the record batchers.

        ***********************************************************************/

        override protected RecordBatch new_record_batch ( )
        {
            return new RecordBatch(this.outer.lzo.lzo);
        }


        /***********************************************************************

            Select event initialiser.

        ***********************************************************************/

        override protected void init_event ( FiberSelectEvent event )
        {
            event.fiber = this.outer.fiber;
        }


        /***********************************************************************

            Loop ceder initialiser.

        ***********************************************************************/

        override protected void init_loop_ceder ( LoopCeder loop_ceder )
        {
            loop_ceder.event = this.event;
        }


        /***********************************************************************

            Request suspender initialiser.

        ***********************************************************************/

        override protected void init_request_suspender
            ( RequestSuspender request_suspender )
        {
            request_suspender.event = this.event;
            request_suspender.nodeitem_ =
                NodeItem(this.outer.conn_pool.address, this.outer.conn_pool.port);
            request_suspender.context_ = this.outer.params.context;
        }
    }


    /***************************************************************************

        Reference to shared resources manager.

    ***************************************************************************/

    private SharedResources shared_resources;


    /***************************************************************************

        Lzo de/compressor, shared by all connections.

    ***************************************************************************/

    private LzoChunkCompressor lzo;


    /***************************************************************************

        Re-usable exception instances for various request handling errors.
        Requests can access these via the getters in DhtRequestResources,
        above.

        TODO: these could probably be shared at a higher level, we probably
        don't need one instance per connection.

    ***************************************************************************/

    private FatalErrorException fatal_error_exception;
    private EmptyValueException empty_value_exception;


    /***************************************************************************

        Constructor

        Params:
            epoll = selector dispatcher instance to register the socket and I/O
                events
            lzo = lzo chunk de/compressor
            conn_pool = interface to an instance of NodeConnectionPool which
                handles assigning new requests to this connection, and recycling
                it when finished
            params = request params instance used internally to store the
                params for the request currently being handled by this
                connection
            fiber_stack_size = size of connection fibers' stack (in bytes)
            shared_resources = reference to shared resources manager

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll, LzoChunkCompressor lzo,
        INodeConnectionPool conn_pool, IRequestParams params,
        size_t fiber_stack_size, SharedResources shared_resources )
    {
        this.lzo = lzo;
        this.shared_resources = shared_resources;

        this.fatal_error_exception = new FatalErrorException;
        this.empty_value_exception = new EmptyValueException;

        super(epoll, conn_pool, params, fiber_stack_size);
    }


    /***************************************************************************

        Command code 'None' handler.

    ***************************************************************************/

    override protected void handleNone ( )
    {
        enforce(false, "Handling command with code None");
    }


    /***************************************************************************

        Command code 'Get' handler.

    ***************************************************************************/

    override protected void handleGetVersion ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(GetVersionRequest)(resources);
    }


    /***************************************************************************

        Command code 'GetResponsibleRange' handler.

    ***************************************************************************/

    override protected void handleGetResponsibleRange ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(GetResponsibleRangeRequest)(resources);
    }


    /***************************************************************************

        Command code 'GetNumConnections' handler.

    ***************************************************************************/

    override protected void handleGetNumConnections ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(GetNumConnectionsRequest)(resources);
    }


    /***************************************************************************

        Command code 'GetChannels' handler.

    ***************************************************************************/

    override protected void handleGetChannels ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(GetChannelsRequest)(resources);
    }


    /***************************************************************************

        Command code 'GetSize' handler.

    ***************************************************************************/

    override protected void handleGetSize ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(GetSizeRequest)(resources);
    }


    /***************************************************************************

        Command code 'GetChannelSize' handler.

    ***************************************************************************/

    override protected void handleGetChannelSize ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(GetChannelSizeRequest)(resources);
    }


    /***************************************************************************

        Command code 'Put' handler.

    ***************************************************************************/

    override protected void handlePut ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(PutRequest)(resources);
    }


    /***************************************************************************

        Command code 'PutBatch' handler.

    ***************************************************************************/

    override protected void handlePutBatch ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(PutBatchRequest)(resources);
    }


    /***************************************************************************

        Command code 'Get' handler.

    ***************************************************************************/

    override protected void handleGet ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(GetRequest)(resources);
    }


    /***************************************************************************

        Command code 'GetAll' handler.

    ***************************************************************************/

    override protected void handleGetAll ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(GetAllRequest)(resources);
    }


    /***************************************************************************

        Command code 'GetAllFilter' handler.

    ***************************************************************************/

    override protected void handleGetAllFilter ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(GetAllFilterRequest)(resources);
    }


    /***************************************************************************

        Command code 'GetAllKeys' handler.

    ***************************************************************************/

    override protected void handleGetAllKeys ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(GetAllKeysRequest)(resources);
    }


    /***************************************************************************

        Command code 'Listen' handler.

    ***************************************************************************/

    override protected void handleListen ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(ListenRequest)(resources);
    }


    /***************************************************************************

        Command code 'Exists' handler.

    ***************************************************************************/

    override protected void handleExists ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(ExistsRequest)(resources);
    }


    /***************************************************************************

        Command code 'Remove' handler.

    ***************************************************************************/

    override protected void handleRemove ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(RemoveRequest)(resources);
    }


    /***************************************************************************

        Command code 'RemoveChannel' handler.

    ***************************************************************************/

    override protected void handleRemoveChannel ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(RemoveChannelRequest)(resources);
    }


    /***************************************************************************

        Command code 'Redistribute' handler.

    ***************************************************************************/

    override protected void handleRedistribute ( )
    {
        scope resources = new DhtRequestResources;
        this.handleCommand!(RedistributeRequest)(resources);
    }
}
