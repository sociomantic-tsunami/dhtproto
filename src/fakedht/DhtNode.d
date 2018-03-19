/*******************************************************************************
    
    Provides simple dht node implementation. Intended to emulate node in tests,
    both in protocol tests and in any client application test suite.

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.DhtNode;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import ocean.util.log.Logger;

import fakedht.ConnectionHandler;

import swarm.node.model.Node;

/*******************************************************************************

    Reference to common fakedht logger instance

*******************************************************************************/

private Logger log;

static this ( )
{
    log = Log.lookup("fakedht");
}

/*******************************************************************************

    Simple DHT node. See fakedht.ConnectionHandler for more
    implementation details

*******************************************************************************/

public class DhtNode
    : NodeBase!(DhtConnectionHandler)
{
    import core.stdc.stdlib : abort;

    import ocean.io.select.client.model.ISelectClient : IAdvancedSelectClient;
    import ocean.net.server.connection.IConnectionHandlerInfo;
    import ocean.io.select.protocol.generic.ErrnoIOException;

    import dhtproto.client.legacy.DhtConst;
    import swarm.node.connection.ConnectionHandler;

    import fakedht.Storage;

    /***************************************************************************

        Flag indicating that unhandled exceptions from the node must be printed
        in test suite trace

    ***************************************************************************/

    private bool log_errors = true;

    /***************************************************************************

        Constructor

        Params:
            node_item = node address & port
            epoll = epoll select dispatcher to be used internally

    ***************************************************************************/

    public this ( DhtConst.NodeItem node_item, EpollSelectDispatcher epoll )
    {
        static immutable backlog = 20;

        auto params = new ConnectionSetupParams;
        params.epoll = epoll;
        params.node_info = this;

        super (node_item, params, backlog);
        this.error_callback = &this.onError;
    }

    /***************************************************************************

        After this method is called, node will stop logging unhandled exceptions
        as part of the test suite trace.

    ***************************************************************************/

    public void ignoreErrors ( )
    {
        this.log_errors = false;
    }

    /***************************************************************************

        Override of standard `stopListener` to also clean fake node listener
        data in global storage.

    ***************************************************************************/

    override public void stopListener ( EpollSelectDispatcher epoll )
    {
        super.stopListener(epoll);
        global_storage.dropAllListeners();
    }

    /***************************************************************************

        Simple `shutdown` implementation to stop logging unhandled exceptions
        when it is initiated.

    ***************************************************************************/

    override public void shutdown ( )
    {
        this.ignoreErrors();
    }

    /***************************************************************************
    
        Make any error fatal

    ***************************************************************************/

    private void onError ( Exception exception, IAdvancedSelectClient.Event,
        IConnectionHandlerInfo )
    {
        if (!this.log_errors)
            return;

        .log.warn("Ignoring exception: {} ({}:{})",
            getMsg(exception), exception.file, exception.line);

        // socket errors can be legitimate, for example if client has terminated
        // the connection early
        if (cast(IOWarning) exception)
            return;

        // can be removed in new major version
        version (none)
        {
            // anything else is unexpected, die at once
            abort();
        }
    }

    /***************************************************************************

        Returns:
            identifier string for this node

    ***************************************************************************/

    override protected cstring id ( )
    {
        return "Fake Turtle DHT Node";
    }
}
