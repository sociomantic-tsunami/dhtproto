/*******************************************************************************

    Test for sending a set of records with sequential keys via Put

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.neo.OrderedPut;

import dhttest.DhtTestCase : NeoDhtTestCase;

/*******************************************************************************

    Checks that a set of records with sequential keys written to the DHT via Put
    are correctly added to the database.

*******************************************************************************/

class OrderedPutTest : NeoDhtTestCase
{
    import dhttest.util.LocalStore;
    import dhttest.util.Record;

    public override Description description ( )
    {
        Description desc;
        desc.name = "Neo ordered Put test";
        return desc;
    }

    public override void run ( )
    {
        LocalStore local;
        NeoVerifier verifier;

        for ( uint i = 0; i < bulk_test_record_count; i++ )
        {
            auto rec = Record.sequential(i);
            this.dht.blocking.put(this.test_channel, rec.key, rec.val);
            local.put(rec.key, rec.val);
        }

        verifier.verifyAgainstDht(local, this.dht, this.test_channel);
    }
}
