/*******************************************************************************

    Class to perform a handshake with all DHT nodes (retrying when it fails),
    providing task helpers that block until one or all nodes are connected.

    Copyright: Copyright (c) 2018 sociomantic labs GmbH.  All rights reserved

    License: Boost Software License Version 1.0.  See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.helper.Handshake;

/// ditto
public class DhtHandshake
{
    import dhtproto.client.DhtClient;
    import dhtproto.client.legacy.internal.helper.RetryHandshake;

    import ocean.task.Scheduler;
    import ocean.task.Task;
    import ocean.task.util.Event;
    import ocean.util.log.Logger;


    /***************************************************************************

        Task that suspends until all nodes are connected

    ***************************************************************************/

    private class AllDhtNodesConnected : Task
    {
        /// Used to manage suspend/resume of this task
        private TaskEvent all_connected_event;

        /***********************************************************************

            Delegate to be called by the handshake once all DHT nodes have
            been reached

        ***********************************************************************/

        private void allNodesConnected ()
        {
            this.outer.log.info("All DHT nodes connected!");
            this.all_connected_event.trigger();
        }

        /***********************************************************************

            Runs the task

        ***********************************************************************/

        protected override void run ()
        {
            this.all_connected_event.wait();
        }
    }


    /***************************************************************************

        Task that suspends until at least one node is connected

    ***************************************************************************/

    private class OneDhtNodeConnected : Task
    {
        import swarm.Const : NodeItem;

        /// Used to manage suspend/resume of this task
        private TaskEvent node_connected_event;

        /***********************************************************************

            Delegate to be called by the handshake each time an individual
            node connects

            Params:
                item = data on the address and port of the connected node

        ***********************************************************************/

        private void oneNodeConnected (NodeItem item)
        {
            this.outer.log.trace("Connected to DHT node {}:{}",
                                 item.Address, item.Port);
            this.node_connected_event.trigger();
        }

        /***********************************************************************

            Runs the task

        ***********************************************************************/

        protected override void run ()
        {
            this.node_connected_event.wait();
        }
    }


    /// Logger for the handshake
    private Logger log;


    /// Instance of task that suspends until all nodes are connected
    private AllDhtNodesConnected all_nodes_connected;


    /// Instance of task that suspends until at least one node is connected
    private OneDhtNodeConnected one_node_connected;


    /// Instance of class that launches the actual handshake, retrying when
    /// it fails until all nodes are connected
    private RetryHandshake retry_handshake;


    /***************************************************************************

        Constructor

        Params:
            dht = DHT client instance via which to perform the handshake
            retry_delay_seconds = time to wait (in seconds) before retrying
                failed handshake attempts

    ***************************************************************************/

    public this (DhtClient dht, size_t retry_delay_seconds)
    in
    {
        assert(dht !is null);
    }
    body
    {
        this.log = Log.lookup("dhtproto.client.legacy.internal.helper.Handshake");

        this.all_nodes_connected = new AllDhtNodesConnected;
        this.one_node_connected = new OneDhtNodeConnected;

        this.retry_handshake =
            new RetryHandshake(theScheduler.epoll, dht, retry_delay_seconds,
                    &this.all_nodes_connected.allNodesConnected,
                    &this.one_node_connected.oneNodeConnected);
    }


    /***************************************************************************

        Returns:
            instance of task that suspends until all nodes have been connected

    ***************************************************************************/

    public AllDhtNodesConnected allNodesConnected ()
    {
        return this.all_nodes_connected;
    }


    /***************************************************************************

        Returns:
            instance of task that suspends until at least one node is connected

    ***************************************************************************/

    public OneDhtNodeConnected oneNodeConnected ()
    {
        return this.one_node_connected;
    }
}

///
unittest
{
    // this example assumes we are already running in
    // a task context
    class HandshakeExample
    {
        import dhtproto.client.DhtClient;

        import ocean.io.Stdout;
        import ocean.task.Scheduler;

        // DHT client to connect with
        private DhtClient dht;

        // The `DhtHandshake` instance may need to persist beyond the
        // end of the `run` method (if e.g. we complete only a partial
        // handshake by the time it exits)
        private DhtHandshake handshake;


        // Set up a DHT client and initialize the handshake, blocking
        // until either the handshake completes, or until at least a
        // partial handshake is complete and more than 60 seconds have
        // passed
        void run ()
        {
            // we assume `theScheduler` is already initialized
            // as this is used internally by `DhtHandshake`
            this.dht = new DhtClient(theScheduler.epoll);

            // start the handshake
            auto retry_delay_seconds = 3;
            this.handshake = new DhtHandshake(this.dht, retry_delay_seconds);

            // block on at least one node connecting
            theScheduler.await(this.handshake.oneNodeConnected());
            Stdout.formatln("At least one node is now connected!");

            // if `theScheduler.awaitOrTimeout` is available, it can
            // be used to implement support for a partial handshake:
            //
            // ```
            // auto timeout_microsec = 60_000_000;
            //
            // auto handshake_timed_out =   /* true if timeout is reached */
            //     theScheduler.awaitOrTimeout(
            //         this.handshake.allNodesConnected(),
            //         timeout_microsec);
            //
            // /* react to `handshake_timed_out` as you wish, but note
            //    that the `DhtHandshake` instance will keep working
            //    in the background to complete the handshake */
            // ```
            //
            // alternatively, we can block on all DHT nodes being
            // connected using `await`:
            theScheduler.await(this.handshake.allNodesConnected());

            Stdout.formatln("DHT handshake complete!");
        }
    }
}
