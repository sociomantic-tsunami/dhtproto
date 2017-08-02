/*******************************************************************************

    Test for sending a batch of records and receiving them back via Listen

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.BatchListen;

/*******************************************************************************

    Imports

*******************************************************************************/

import dhttest.DhtTestCase;

/*******************************************************************************

    Checks that a series of records written to the DHT are received back via a
    listener.

*******************************************************************************/

class BatchListenTest : DhtTestCase
{
    import dhttest.util.Record;

    public override Description description ( )
    {
        Description desc;
        desc.name = "Batch Listen test";
        return desc;
    }

    public override void run ( )
    {
        auto listener = this.dht.startListen(this.test_channel);

        for ( uint i = 0; i < bulk_test_record_count; i++ )
        {
            // Send record to DHT
            auto rec = Record.sequential(i);
            this.dht.put(this.test_channel, rec.key, rec.val);

            // Wait for it to arrive back via the listener
            listener.waitNextEvent();
            test!("==")(listener.data.length, 1);
            test!("in")(rec.key, listener.data);
            test!("==")(listener.data[rec.key], rec.val);

            // Clear the listener's map of received records
            listener.data.remove(rec.key);
            test!("==")(listener.data.length, 0);
        }
    }
}

