/*******************************************************************************

    Test for removing a set of records with sequential keys via Remove

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.OrderedRemove;

/*******************************************************************************

    Imports

*******************************************************************************/

import dhttest.DhtTestCase;

/*******************************************************************************

    Checks that a set of records with sequential keys written to the DHT via Put
    and then partially (50%) removed via Remove are correctly updated in the
    database.

*******************************************************************************/

class OrderedRemoveTest : DhtTestCase
{
    import dhttest.util.LocalStore;
    import dhttest.util.Record;

    public override Description description ( )
    {
        Description desc;
        desc.name = "Ordered Remove test";
        return desc;
    }

    public override void run ( )
    {
        LocalStore local;
        LegacyVerifier verifier;

        // Put some records
        for ( uint i = 0; i < bulk_test_record_count; i++ )
        {
            auto rec = Record.sequential(i);
            this.dht.put(this.test_channel, rec.key, rec.val);
            local.put(rec.key, rec.val);
        }

        verifier.verifyAgainstDht(local, this.dht, this.test_channel);

        // Remove half of them
        for ( uint i = 0; i < bulk_test_record_count; i += 2 )
        {
            auto rec = Record.sequential(i);
            this.dht.remove(this.test_channel, rec.key);
            local.remove(rec.key);
        }

        verifier.verifyAgainstDht(local, this.dht, this.test_channel);
    }
}

