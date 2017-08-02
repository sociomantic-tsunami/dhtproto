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
