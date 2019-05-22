/*******************************************************************************

    Tests for the neo Remove request.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.neo.Remove;

import ocean.transition;
import dhttest.DhtTestCase : NeoDhtTestCase;

/*******************************************************************************

    Checks that a set of records written to the DHT via Put are correctly
    removed via Remove.

*******************************************************************************/

class PutRemoveTest : NeoDhtTestCase
{
    import dhttest.util.LocalStore;
    import dhttest.util.Record;

    public override Description description ( )
    {
        Description desc;
        desc.name = "Neo Put / Remove test";
        return desc;
    }

    public override void run ( )
    {
        LocalStore local;
        NeoVerifier verifier;

        // Put some records.
        for ( uint i = 0; i < bulk_test_record_count; i++ )
        {
            auto rec = Record.sequential(i);
            this.dht.blocking.put(this.test_channel, rec.key, rec.val);
            local.put(rec.key, rec.val);
        }

        // Remove half of them.
        for ( uint i = 0; i < bulk_test_record_count; i += 2 )
        {
            auto rec = Record.sequential(i);
            this.dht.blocking.remove(this.test_channel, rec.key);
            local.remove(rec.key);
        }

        verifier.verifyAgainstDht(local, this.dht, this.test_channel);
    }
}
