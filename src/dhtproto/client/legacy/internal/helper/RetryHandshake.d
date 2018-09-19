/*******************************************************************************

    Class to do a node handshake and to retry when it fails

    The handshake callback is optional. When you are just calling the eventloop
    to wait till the handshake is done, you don't need a callback.

    Copyright:
        Copyright (c) 2012-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.helper.RetryHandshake;

/// ditto
class RetryHandshake
{
    import swarm.Const : NodeItem;
    import dhtproto.client.DhtClient;
    import dhtproto.client.legacy.internal.registry.model.IDhtNodeRegistryInfo;

    import ocean.io.select.EpollSelectDispatcher;
    import ocean.io.select.client.TimerEvent;
    import ocean.util.log.Logger;

    /// Logger for instances of this class.
    /// Note: in theory, an application may have multiple instances of this
    /// class. Currently, these will all write to the same logger (which will
    /// result in a confusing mess). This is a highly unusual case, though,
    /// so is not specifically supported. We can add better support, if it's
    /// ever needed.
    private Logger retry_log;

    /// Timer to retry the handshake.
    protected TimerEvent timer;

    /// DHT client to use to perform handshakes.
    protected DhtClient dht;

    /// Epoll instance to register timer with.
    protected EpollSelectDispatcher epoll;

    /// Time to wait (in seconds) before retrying, after an incomplete
    /// handshake.
    protected size_t wait_time;

    /// Set of nodes which have already handshaken succesfully. (Nodes are only
    /// added to this set, never removed.)
    private bool[hash_t] established_nodes;

    /// Delegate that will be called on success of a complete handshake (i.e.
    /// the handshake has succeeded for every node).
    protected void delegate ( ) handshake_complete_dg;

    /// Delegate that will be called on the first successful handshake with each
    /// individual node.
    protected void delegate ( NodeItem ) one_node_handshake_dg;

    /***************************************************************************

        Constructor. Initiates the handshake (and the retrying process, if the
        handshake does not complete on the first attempt).

        Params:
            epoll = epoll instance
            dht = dht client
            wait_time = time to wait (in seconds) before retrying, after an
                incomplete handshake
            handshake_complete_dg = delegate to call on success, optional
            one_node_handshake_dg = delegate to call on connecting to one node,
                optional

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll, DhtClient dht,
        size_t wait_time, void delegate ( ) handshake_complete_dg = null,
        void delegate ( NodeItem ) one_node_handshake_dg = null )
    {
        this.wait_time = wait_time;

        this.dht = dht;

        this.handshake_complete_dg = handshake_complete_dg;
        this.one_node_handshake_dg = one_node_handshake_dg;

        this.epoll = epoll;

        this.timer = new TimerEvent(&this.tryHandshake);

        this.retry_log = Log.lookup("RetryHandshake");

        this.tryHandshake();
    }

    /***************************************************************************

        Try doing the handshake.

        Returns:
            false, so the timer doesn't stay registered. (Re-registering the
            timer is handled by the `result` method.)

    ***************************************************************************/

    protected bool tryHandshake ( )
    {
        this.retry_log.info("Attempting handshake.");
        this.dht.nodeHandshake(&this.result, &this.handshake_notifier);

        return false;
    }

    /***************************************************************************

        Handshake callback. Calls the user delegate on success, else retries the
        handshake after the specified wait time.

        Params:
            success = whether the handshake was a success

    ***************************************************************************/

    private void result ( DhtClient.RequestContext, bool success )
    {
        if ( !success )
        {
            this.error();

            this.retry_log.info("Handshake did not succeed for all nodes. Retrying in {}s",
                this.wait_time);
            this.epoll.register(this.timer);
            this.timer.set(this.wait_time, 0, 0, 0);
        }
        else
        {
            this.retry_log.info("Handshake succeeded for all nodes.");
            this.success();

            if ( this.handshake_complete_dg !is null )
            {
                this.handshake_complete_dg();
            }
        }
    }

    /***************************************************************************

        Handshake notifier callback. Calls the one-node connected delegate, if
        provided, when a node connects initially.

        Params:
            info = DHT request notification for one of the requests involved in
                the handshake

    ***************************************************************************/

    private void handshake_notifier ( DhtClient.RequestNotification info )
    {
        this.retry_log.trace("Callback: {}", info.message(this.dht.msg_buf));

        this.nodeHandshakeCB(info);

        if ( info.type != info.type.Finished )
            return;

        if ( this.one_node_handshake_dg is null )
            return;

        // Search for this node in the client's registry.
        auto dht_registry = cast(IDhtNodeRegistryInfo)this.dht.nodes;
        foreach ( node; dht_registry )
        {
            if ( node.address != info.nodeitem.Address ||
                 node.port != info.nodeitem.Port )
                continue;

            // If this node is now connected for the first time, call the
            // user's delegate.
            auto node_hash = info.nodeitem.toHash();
            if ( !(node_hash in this.established_nodes)
                && node.api_version_ok && node.hash_range_queried )
            {
                this.established_nodes[node_hash] = true;
                this.one_node_handshake_dg(info.nodeitem);
                this.retry_log.info("Handshake succeeded on {}:{}.",
                    info.nodeitem.Address, info.nodeitem.Port);
            }
        }
    }

    /***************************************************************************

        Optionally overrideable handshake notifier callback, called from
        handshake_notifier().

        Params:
            info = DHT request notification for one of the requests involved in
                the handshake

    ***************************************************************************/

    protected void nodeHandshakeCB ( DhtClient.RequestNotification info ) {   }

    /***************************************************************************

        Called when the handshake failed and it will be retried.

    ***************************************************************************/

    protected void error (  ) {    }

    /***************************************************************************

        Called when the handshake succeeded and the user delegate will be
        called.

    ***************************************************************************/

    protected void success ( ) {    }
}

///
unittest
{
    struct HandshakeExample
    {
        import ocean.io.select.EpollSelectDispatcher;
        import ocean.io.Stdout;

        import swarm.Const : NodeItem;
        import dhtproto.client.DhtClient;
        import dhtproto.client.legacy.internal.helper.RetryHandshake;

        // Epoll instance.
        private EpollSelectDispatcher epoll;

        // DHT client to connect with.
        private DhtClient dht;

        // Set up epoll and a DHT client, initiate the handshake, and start the
        // event loop running.
        void main ( )
        {
            this.epoll = new EpollSelectDispatcher;
            this.dht = new DhtClient(this.epoll);
            // In a real app, you should call `this.dht.addNodes(...);`

            // Start the handshake
            auto retry_delay_seconds = 3;
            // Store the reference to the RetryHandshake
            // object so it doesn't get garbage collected.
            auto handshake = new RetryHandshake(this.epoll, this.dht, retry_delay_seconds,
                &this.handshake_complete_dg, &this.node_connected_dg);

            this.epoll.eventLoop();
        }

        // Called when an individual node is initially connected.
        private void node_connected_dg ( NodeItem node )
        {
            Stdout.formatln("{}:{} connected", node.Address, node.Port);
        }

        // Called when the handshake has connected to all nodes in the DHT.
        // (Note that this is not a guarantee that all nodes are currently
        // contactable; it merely indicates that they have all been handshaked
        // at some point.)
        private void handshake_complete_dg ( )
        {
            Stdout.formatln("Handshake complete");
        }
    }
}
