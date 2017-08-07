/*******************************************************************************
    
    Common base for all dhttest test cases. Provides DHT client instance and
    defines standard name for tested channel. Automatically performs DHT
    client handshake before test starts.

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.DhtTestCase;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import turtle.TestCase;

/*******************************************************************************

    Legacy test case base. Actual tests are located in `dhttest.cases`.

*******************************************************************************/

abstract class DhtTestCase : TestCase
{
    import ocean.core.Test; // makes `test` available in derivatives
    import dhttest.DhtClient;

    /***************************************************************************

        Number of records handled in bulk tests. (This value is used by all test
        cases which test reading/writing/removing a large number of records from
        the DHT. Small sanity check test cases do not use it.)

    ***************************************************************************/

    public static size_t bulk_test_record_count = 10_000;

    /***************************************************************************

        DHT client to use in tests. Provides blocking fiber API.

    ***************************************************************************/

    protected DhtClient dht;

    /***************************************************************************

        Standard name for a channel with test data which will be cleaned
        automatically after the test case ends.

    ***************************************************************************/

    protected istring test_channel;

    /***************************************************************************

        Constructor

    ***************************************************************************/

    this ( )
    {
        this.test_channel = "test_channel";
    }

    /***************************************************************************

        Creates new DHT client for a test case and proceeds with handshake so
        that client instance will be ready to work by the time `run` methods
        is being run.

    ***************************************************************************/

    override public void prepare ( )
    {
        this.dht = new DhtClient;
        this.dht.handshake(10000);
    }

    /***************************************************************************

        Deletes test channel each time test case finishes to avoid using
        some state by accident between tests.

    ***************************************************************************/

    override public void cleanup ( )
    {
        this.dht.removeChannel(this.test_channel);
    }
}

/*******************************************************************************

    Neo test case base. Actual tests are located in `dhttest.cases.neo`.

*******************************************************************************/

abstract class NeoDhtTestCase : TestCase
{
    import ocean.core.Test; // makes `test` available in derivatives
    import ocean.core.Enforce;
    import ocean.task.Scheduler;
    import ocean.task.Task;
    import ocean.util.log.Log;
    import dhtproto.client.DhtClient;
    import Legacy = dhttest.DhtClient;
    import swarm.neo.authentication.HmacDef: Key;

    /***************************************************************************

        Reference to common test case logger instance

    ***************************************************************************/

    private Logger log;

    /***************************************************************************

        Number of records handled in bulk tests. (This value is used by all test
        cases which test reading/writing/removing a large number of records from
        the DHT. Small sanity check test cases do not use it.)

    ***************************************************************************/

    public static size_t bulk_test_record_count = 10_000;

    /***************************************************************************

        DHT client to use in tests. Provides blocking fiber API.

    ***************************************************************************/

    protected DhtClient dht;

    /***************************************************************************

        Standard name for a channel with test data which will be cleaned
        automatically after the test case ends.

    ***************************************************************************/

    protected istring test_channel;

    /***************************************************************************

        Task being suspended during connection.

    ***************************************************************************/

    private Task connect_task;

    /***************************************************************************

        Flag indicating that a connection error occurred.

    ***************************************************************************/

    private bool connect_error;

    /***************************************************************************

        Constructor

    ***************************************************************************/

    this ( )
    {
        this.log = Log.lookup("dhttest");
        this.test_channel = "test_channel";
    }

    /***************************************************************************

        Creates new DHT client for a test case and proceeds with handshake so
        that client instance will be ready to work by the time `run` method
        is called.

    ***************************************************************************/

    override public void prepare ( )
    {
        cstring auth_name = "test";
        auto auth_key = Key.init;
        const max_connections = 2;
        this.dht = new DhtClient(theScheduler.epoll, auth_name,
            auth_key.content, &this.neoConnectionNotifier, max_connections);
        this.dht.neo.enableSocketNoDelay();

        this.connect(10000);
    }

    /***************************************************************************

        Shuts down the client's connections, to avoid the connection notifier
        being called (when the node shuts down) after the client has been
        deleted.

        Also deletes test channel each time a test case finishes, to avoid using
        some state by accident between tests. Note that for the moment, this
        uses the legacy protocol, as no neo RemoveChannel request exists.

    ***************************************************************************/

    override public void cleanup ( )
    {
        this.log.info("Shutting down client -- node connection error expected");
        this.dht.neo.shutdown();

        auto legacy_dht = new Legacy.DhtClient;
        legacy_dht.handshake(10000);
        legacy_dht.removeChannel(this.test_channel);
    }

    /***************************************************************************

        Connects to the neo ports of the DHT node. The test Task is suspended
        until connection has succeeded.

        Params:
            legacy_port = DHT node legacy port. (The neo port is +100, by
                convention, currently. See
                dhtnode.node.DhtHashRange.newNodeAdded().)

    ***************************************************************************/

    public void connect ( ushort legacy_port )
    {
        this.connect_task = Task.getThis();
        assert(this.connect_task !is null);

        this.dht.neo.addNode("127.0.0.1".dup, cast(ushort)(legacy_port + 100));

        scope stats = this.dht.neo.new DhtStats;
        while ( stats.num_nodes_known_hash_range < stats.num_registered_nodes )
        {
            enforce(!this.connect_error, "Test DHT neo connection error");
            this.connect_task.suspend();
        }
    }

    /***************************************************************************

        Connects to the legacy port of the DHT node. The test Task is suspended
        until connection has succeeded.

        Params:
            legacy_port = DHT node legacy port

    ***************************************************************************/

    public void legacyConnect ( ushort legacy_port )
    {
        this.dht.addNode("127.0.0.1".dup, legacy_port);

        auto task = Task.getThis();
        assert(task !is null);

        bool ok, finished;

        void handshake_cb ( DhtClient.RequestContext, bool ok_ )
        {
            finished = true;
            ok = ok_;
            if ( task.suspended() )
                task.resume();
        }

        this.dht.nodeHandshake(&handshake_cb, null);
        if ( !finished )
            task.suspend();

        enforce(ok, "Legacy DHT handshake failed");
    }

    /***************************************************************************

        Neo connection notifier.

        Params:
            info = notification info

    ***************************************************************************/

    private void neoConnectionNotifier ( DhtClient.Neo.DhtConnNotification info )
    {
        with ( info.Active ) switch ( info.active )
        {
            case connection_error:
                this.connect_error = true;
                this.log.warn("Neo connection error on {}:{}: {} @ {}:{}",
                    info.connection_error.node_addr.address_bytes,
                    info.connection_error.node_addr.port,
                    getMsg(info.connection_error.e),
                    info.connection_error.e.file, info.connection_error.e.line);
                break;

            case connected:
            case hash_range_queried:
                break;

            default: assert(false);
        }

        this.connect_task.resume();
    }
}

