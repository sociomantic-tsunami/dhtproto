/*******************************************************************************

    Tests for the neo Put request.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.neo.Put;

import ocean.transition;
import dhttest.DhtTestCase : NeoDhtTestCase;

/*******************************************************************************

    Test for record value size limit.

*******************************************************************************/

class ValueTooBig : NeoDhtTestCase
{
    import dhtproto.client.request.Put : MaxRecordSize;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Put of a too big record value";
        return desc;
    }

    public override void run ( )
    {
        // Put a record of exactly MaxRecordSize bytes.
        hash_t key;
        mstring val;
        val.length = MaxRecordSize;
        auto res = this.dht.blocking.put(this.test_channel, key, val);
        test(res.succeeded);

        // Put a too big record.
        val.length = MaxRecordSize + 1;
        res = this.dht.blocking.put(this.test_channel, key, val);
        test(!res.succeeded);
    }
}

/*******************************************************************************

    Checks that large records can be fetched back from the DHT and that records
    over the size limit are not stored.

*******************************************************************************/

class LargeValueFetchTest : NeoDhtTestCase
{
    import dhtproto.client.request.Put : MaxRecordSize;
    import dhttest.util.LocalStore;

    public override Description description ( )
    {
        Description desc;
        desc.name = "Neo Put and fetch of large records";
        return desc;
    }

    public override void run ( )
    {
        LocalStore local;
        NeoVerifier verifier;

        // Put a record of exactly MaxRecordSize bytes.
        hash_t key;
        mstring val;
        val.length = MaxRecordSize;
        auto res = this.dht.blocking.put(this.test_channel, key, val);
        test(res.succeeded);
        local.put(key, val);

        // Put a too big record.
        val.length = MaxRecordSize + 1;
        res = this.dht.blocking.put(this.test_channel, key, val);
        test(!res.succeeded);

        // Check that only the first record made it to the DHT and that it is
        // returned by all get requests.
        verifier.verifyAgainstDht(local, this.dht, this.test_channel);
    }
}
