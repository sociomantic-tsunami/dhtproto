/*******************************************************************************

    Test for sending a set of records with non-sequential keys via Put

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.UnorderedPut;

/*******************************************************************************

    Imports

*******************************************************************************/

import dhttest.DhtTestCase;

/*******************************************************************************

    Checks that a set of records with non-sequential keys written to the DHT via
    Put are correctly added to the database.

*******************************************************************************/

class UnorderedPutTest : DhtTestCase
{
    import dhttest.util.LocalStore;
    import dhttest.util.Record;

    public override Description description ( )
    {
        Description desc;
        desc.name = "Unordered Put test";
        return desc;
    }

    public override void run ( )
    {
        LocalStore local;
        LegacyVerifier verifier;

        for ( uint i = 0; i < bulk_test_record_count; i++ )
        {
            auto rec = Record.spread(i);
            this.dht.put(this.test_channel, rec.key, rec.val);
            local.put(rec.key, rec.val);
        }

        verifier.verifyAgainstDht(local, this.dht, this.test_channel);
    }
}

