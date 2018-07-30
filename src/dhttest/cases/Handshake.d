/*******************************************************************************

    Basic sanity test that ensures that handshake with tested DHT node can
    be established. All other tests don't make any sense if this fails.

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.Handshake;

/*******************************************************************************

    Imports

*******************************************************************************/

import dhttest.DhtTestCase;

/*******************************************************************************

    Basic sanity test that ensures that handshake with tested DHT node can
    be established. All other tests don't make any sense if this fails.

*******************************************************************************/

class Handshake : DhtTestCase
{
    import dhttest.DhtClient;

    import ocean.core.Test;

    override public Description description ( )
    {
        Description desc;
        desc.priority = 1000; // must run first
        desc.name = "Handshake / Sanity";
        desc.fatal = true;
        return desc;
    }

    override public void prepare ( )
    {
        // Base `prepare` also does handshake but for this specific case it needs
        // to be done in `run` so that proper test failure reporting will be done
        // by test runner.
        this.dht = new DhtClient;
    }

    override public void run ( )
    {
        this.dht.handshake(10000);
        test(this.dht.hasCompletedHandshake);
    }

    override public void cleanup ( )
    {
        // do nothing, there is no channel to delete anyway and it will crash
        // trying to do so if handshake fails
    }
}
