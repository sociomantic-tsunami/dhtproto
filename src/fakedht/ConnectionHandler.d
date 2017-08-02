/*******************************************************************************

    Forwards DHT requests to fakedht request implementations
    in fakedht.request.*

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.ConnectionHandler;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.util.log.Log;

import ocean.net.server.connection.IConnectionHandler;

import swarm.node.connection.ConnectionHandler;
import dhtproto.client.legacy.DhtConst;

import ocean.transition;

/*******************************************************************************

    Reference to common fakedht logger instance

*******************************************************************************/

private Logger log;

static this ( )
{
    log = Log.lookup("fakedht");
}

/*******************************************************************************

    Simple DHT connection handler. Implements requests in terms
    of trivial array based storage backend.

*******************************************************************************/

public class DhtConnectionHandler :
    ConnectionHandlerTemplate!(DhtConst.Command)
{
    import ocean.io.select.client.FiberSelectEvent;
    import dhtproto.node.request.model.DhtCommand;

    import fakedht.request.Exists;
    import fakedht.request.Get;
    import fakedht.request.GetAll;
    import fakedht.request.GetAllFilter;
    import fakedht.request.GetAllKeys;
    import fakedht.request.GetChannelSize;
    import fakedht.request.GetChannels;
    import fakedht.request.GetNumConnections;
    import fakedht.request.GetResponsibleRange;
    import fakedht.request.GetSize;
    import fakedht.request.GetVersion;
    import fakedht.request.Listen;
    import fakedht.request.Put;
    import fakedht.request.PutBatch;
    import fakedht.request.Redistribute;
    import fakedht.request.Remove;
    import fakedht.request.RemoveChannel;

    import ocean.io.Stdout : Stderr;
    import core.stdc.stdlib : abort;

    /***************************************************************************

        Creates resources needed by the protocol in most straighforward way,
        allocating new GC chunk each time.

    ***************************************************************************/

    private scope class DhtRequestResources : DhtCommand.Resources
    {
        import dhtproto.node.request.params.RedistributeNode;
        import swarm.util.RecordBatcher;
        import ocean.io.compress.Lzo;

        /***********************************************************************

            Backs all resource getters.

            Struct wrapper is used to workaround D inability to allocate slice
            itself on heap via `new`.

        ***********************************************************************/

        struct Buffer
        {
            mstring data;
        }

        /***********************************************************************

            Used to write channel names to

        ***********************************************************************/

        override public mstring* getChannelBuffer ( )
        {
            return &((new Buffer).data);
        }

        /***********************************************************************

            Used to write key arguments to

        ***********************************************************************/

        override public mstring* getKeyBuffer ( )
        {
            return &((new Buffer).data);
        }

        /***********************************************************************

            Used to write filter argument to

        ***********************************************************************/

        override public mstring* getFilterBuffer ( )
        {
            return &((new Buffer).data);
        }

        /***********************************************************************

            Used to write value argument to

        ***********************************************************************/

        override public mstring* getValueBuffer ( )
        {
            return &((new Buffer).data);
        }

        /***********************************************************************

            Used to write temporary buffer before decompression for batch
            requests

        ***********************************************************************/

        override public mstring* getDecompressBuffer ( )
        {
            return &((new Buffer).data);
        }

        /***********************************************************************

            Used as target compression buffer

        ***********************************************************************/

        ubyte[]* getCompressBuffer ( )
        {
            return cast(ubyte[]*) &((new Buffer).data);
        }

        /***********************************************************************

           Object that does data compression

        ***********************************************************************/

        RecordBatcher getRecordBatcher ( )
        {
            return new RecordBatcher(new Lzo);
        }

        /***********************************************************************

           Object that does data decompression

        ***********************************************************************/

        RecordBatch getRecordBatch ( )
        {
            return new RecordBatch(new Lzo);
        }

        /***********************************************************************

            Redistribution is not supported by fake node

        ***********************************************************************/

        RedistributeNode[]* getRedistributeNodeBuffer ( )
        {
            assert (false);
        }
    }

    /***************************************************************************

        Select event used by some requests to suspend execution until some
        event occurs.

    ***************************************************************************/

    private FiberSelectEvent event;

    /***************************************************************************

        Constructor.

        Params:
            finalize_dg = user-specified finalizer, called when the connection
                is shut down
            setup = struct containing everything needed to set up a connection

    ***************************************************************************/

    public this (void delegate(IConnectionHandler) finalize_dg,
        ConnectionSetupParams setup )
    {
        super(finalize_dg, setup);

        this.event = new FiberSelectEvent(this.writer.fiber);
    }

    /***************************************************************************

        Command code 'None' handler. Treated the same as an invalid command
        code.

    ***************************************************************************/

    override protected void handleNone ( )
    {
        this.handleInvalidCommand();
    }

    /***************************************************************************

        Command code 'GetVersion' handler.

    ***************************************************************************/

    override protected void handleGetVersion ( )
    {
        this.handleCommand!(GetVersion);
    }


    /***************************************************************************

        Command code 'GetResponsibleRange' handler.

    ***************************************************************************/

    override protected void handleGetResponsibleRange ( )
    {
        this.handleCommand!(GetResponsibleRange);
    }


    /***************************************************************************

        Command code 'GetNumConnections' handler.

    ***************************************************************************/

    override protected void handleGetNumConnections ( )
    {
        this.handleCommand!(GetNumConnections);
    }


    /***************************************************************************

        Command code 'GetChannels' handler.

    ***************************************************************************/

    override protected void handleGetChannels ( )
    {
        this.handleCommand!(GetChannels);
    }


    /***************************************************************************

        Command code 'GetSize' handler.

    ***************************************************************************/

    override protected void handleGetSize ( )
    {
        this.handleCommand!(GetSize);
    }


    /***************************************************************************

        Command code 'GetChannelSize' handler.

    ***************************************************************************/

    override protected void handleGetChannelSize ( )
    {
        this.handleCommand!(GetChannelSize);
    }


    /***************************************************************************

        Command code 'Put' handler.

    ***************************************************************************/

    override protected void handlePut ( )
    {
        this.handleCommand!(Put);
    }


    /***************************************************************************

        Command code 'PutBatch' handler.

    ***************************************************************************/

    override protected void handlePutBatch ( )
    {
        this.handleCommand!(PutBatch);
    }


    /***************************************************************************

        Command code 'Get' handler.

    ***************************************************************************/

    override protected void handleGet ( )
    {
        this.handleCommand!(Get);
    }


    /***************************************************************************

        Command code 'GetAll' handler.

    ***************************************************************************/

    override protected void handleGetAll ( )
    {
        this.handleCommand!(GetAll);
    }


    /***************************************************************************

        Command code 'GetAllFilter' handler.

    ***************************************************************************/

    override protected void handleGetAllFilter ( )
    {
        this.handleCommand!(GetAllFilter);
    }


    /***************************************************************************

        Command code 'GetAllKeys' handler.

    ***************************************************************************/

    override protected void handleGetAllKeys ( )
    {
        this.handleCommand!(GetAllKeys);
    }


    /***************************************************************************

        Command code 'Listen' handler.

    ***************************************************************************/

    override protected void handleListen ( )
    {
        this.handleCommand!(Listen);
    }


    /***************************************************************************

        Command code 'Exists' handler.

    ***************************************************************************/

    override protected void handleExists ( )
    {
        this.handleCommand!(Exists);
    }


    /***************************************************************************

        Command code 'Remove' handler.

    ***************************************************************************/

    override protected void handleRemove ( )
    {
        this.handleCommand!(Remove);
    }


    /***************************************************************************

        Command code 'RemoveChannel' handler.

    ***************************************************************************/

    override protected void handleRemoveChannel ( )
    {
        this.handleCommand!(RemoveChannel);
    }


    /***************************************************************************

        Command code 'Redistribute' handler.

    ***************************************************************************/

    override protected void handleRedistribute ( )
    {
        this.handleCommand!(Redistribute);
    }

    /***************************************************************************

        Command handler method template.

        Template params:
            Handler = type of request handler

    ***************************************************************************/

    private void handleCommand ( Handler : DhtCommand ) ( )
    {
        .log.trace("handling {}", Handler.stringof);

        scope resources = new DhtRequestResources;
        scope handler = new Handler(this.reader, this.writer, this.event,
            resources);

        static mstring buffer;
        scope(success)
            .log.trace("successfully handled {}", handler.description(buffer));
        scope(failure)
            .log.trace("failure while handling {}", handler.description(buffer));

        handler.handle();
    }

    /***************************************************************************

        Called when a connection is finished. Unregisters the reader & writer
        from epoll and closes the connection socket (via
        IConnectionhandler.finalize()).

    ***************************************************************************/

    public override void finalize ( )
    {
        this.writer.fiber.epoll.unregister(this.writer);
        this.writer.fiber.epoll.unregister(this.reader);
        super.finalize();
    }
}
