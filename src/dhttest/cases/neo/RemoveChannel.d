/*******************************************************************************

    Test cases for the neo RemoveChannel request.

    Note that a test case for the behaviour of removing a mirrored channel is
    in dhttest.cases.neo.Mirror. (It was more convenient to write there due to
    the existing framework in that module for handling Mirror requests.)

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.neo.RemoveChannel;

import ocean.meta.types.Qualifiers;
import ocean.core.Test;
import dhttest.DhtTestCase : NeoDhtTestCase;
import dhtproto.client.DhtClient;

/*******************************************************************************

    Simple test of removing a channel after writing a record to it.

*******************************************************************************/

class RemoveChannel : NeoDhtTestCase
{
    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Put then RemoveChannel";
        return desc;
    }

    public override void run ( )
    {
        // Put a record.
        hash_t key;
        auto put_res = this.dht.blocking.put(this.test_channel, key, "hi");
        test(put_res.succeeded);

        // Check that it's in the channel.
        void[] buf;
        auto get_res = this.dht.blocking.get(this.test_channel, key, buf);
        test(get_res.succeeded);
        test(get_res.value == "hi");

        // Remove the channel.
        auto rem_res = this.dht.blocking.removeChannel(this.test_channel);
        test(rem_res.succeeded);

        // Check that the put record is no longer in the channel.
        get_res = this.dht.blocking.get(this.test_channel, key, buf);
        test(get_res.succeeded);
        test(get_res.value == "");
    }
}
