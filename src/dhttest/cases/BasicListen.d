/*******************************************************************************

    Collection of tests for Listen request

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.BasicListen;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhttest.DhtTestCase;

import ocean.core.Test;
import ocean.io.select.fiber.SelectFiber;
import ocean.io.select.client.FiberTimerEvent;

const PRIORITY = 90;

/*******************************************************************************

    Tests the behaviour of a running Listen request then removing the channel
    being listened to.

    An active Listen request prevents a channel from being removed.

*******************************************************************************/

class ListenRemoveChannel : DhtTestCase
{
    override public Description description ( )
    {
        Description desc;
        desc.priority = PRIORITY;
        desc.name = "RemoveChannel is rejected on a listened channel";
        return desc;
    }

    override public void run ( )
    {
        auto listener = this.dht.startListen(this.test_channel);
        const key = 0;
        this.dht.put(this.test_channel, key, "whatever"[]);
        listener.waitNextEvent();
        test(!listener.finished);
        listener.data.remove(key); // Clear record before calling waitNextEvent()

        testThrown(this.dht.removeChannel(this.test_channel));
    }
}

/*******************************************************************************

    Tests the behaviour of a Put request, which should trigger a waiting
    Listen on the same channel.

*******************************************************************************/

class ListenTrigger : DhtTestCase
{
    import Hash = swarm.util.Hash;

    override public Description description ( )
    {
        Description desc;
        desc.priority = PRIORITY;
        desc.name = "Listen gets activated by Put";
        return desc;
    }

    override public void run ( )
    {
        auto listener = this.dht.startListen(this.test_channel);

        const key = 5;
        this.dht.put(this.test_channel, key, "value"[]);
        listener.waitNextEvent();
        test!("==")(listener.data.length, 1);
        test!("in")(key, listener.data);
        test!("==")(listener.data[key], "value");
    }
}
