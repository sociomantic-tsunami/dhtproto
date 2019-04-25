/*******************************************************************************

    Map used to verify the results of operations on the DHT being tested.

    When used in tests, the map should be updated in the same way as the DHT
    being tested (e.g. when a record is put to the DHT, the same record should
    be put to the map). The verifyAgainstDht() method then performs a thorough
    series of tests to confirm that the content of the DHT exactly matches the
    content of the map.

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.util.LocalStore;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

/*******************************************************************************

    Local storage map wrapper

*******************************************************************************/

struct LocalStore
{
    /***************************************************************************

        Map of data in local store

    ***************************************************************************/

    private mstring[hash_t] data;

    /***************************************************************************

        Adds a record to the local store.

        Params:
            key = record key
            val = record value

    ***************************************************************************/

    public void put ( hash_t key, cstring val )
    {
        this.data[key] = val.dup;
    }

    /***************************************************************************

        Removes a record from the local store.

        Params:
            key = key to remove

    ***************************************************************************/

    public void remove ( hash_t key )
    {
        this.data.remove(key);
    }
}

/*******************************************************************************

    Verifier which checks the contents of the DHT, using legacy requests,
    against the contents of a LocalStore instance.

*******************************************************************************/

public struct LegacyVerifier
{
    import dhttest.DhtClient;
    import turtle.runner.Logging;
    import ocean.core.array.Search : contains;
    import ocean.core.Test;

    /// LocalStore to check against. Set in verifyAgainstDht.
    private LocalStore* local;

    /***************************************************************************

        Performs a series of tests to confirm that the content of the DHT
        exactly matches the content of the map.

        Params:
            local = LocalStore instance to check against
            dht = DHT client to use to perform tests
            channel = name of channel to compare against in DHT

        Throws:
            TestException upon verification failure

    ***************************************************************************/

    public void verifyAgainstDht ( ref LocalStore local, DhtClient dht,
        cstring channel )
    {
        this.local = &local;

        this.verifyGetChannelSize(dht, channel);
        this.verifyGetAll(dht, channel);
        this.verifyGetAllFilter(dht, channel);
        this.verifyGetAllKeys(dht, channel);
        this.verifyExists(dht, channel);
        this.verifyGet(dht, channel);
    }

    /***************************************************************************

        Compares the number of records in the DHT channel against the number of
        records in the local store, using a DHT GetChannelSize request.

        Params:
            dht = DHT client to use to perform tests
            channel = name of channel to compare against in DHT

        Throws:
            TestException upon verification failure

    ***************************************************************************/

    private void verifyGetChannelSize ( DhtClient dht, cstring channel )
    {
        ulong records, bytes;
        dht.getChannelSize(channel, records, bytes);
        log.trace("\tVerifying channel with GetChannelSize: local:{}, remote:{}",
            this.local.data.length, records);
        test!("==")(this.local.data.length, records);
    }

    /***************************************************************************

        Compares all records in the DHT channel against the records in the local
        store, using a DHT GetAll request.

        Params:
            dht = DHT client to use to perform tests
            channel = name of channel to compare against in DHT

        Throws:
            TestException upon verification failure

    ***************************************************************************/

    private void verifyGetAll ( DhtClient dht, cstring channel )
    {
        auto remote = dht.getAll(channel);
        log.trace("\tVerifying channel with GetAll: local:{}, remote:{}",
            this.local.data.length, remote.length);
        test!("==")(this.local.data.length, remote.length);

        foreach ( k, v; remote )
        {
            test!("in")(k, this.local.data);
            test!("==")(v, this.local.data[k]);
        }
    }

    /***************************************************************************

        Compares all records in the DHT channel against the records in the local
        store, with a standard string-match filter applied to both (the filter
        passes records which contain the character "0"), using a DHT
        GetAllFilter request.

        Params:
            dht = DHT client to use to perform tests
            channel = name of channel to compare against in DHT

        Throws:
            TestException upon verification failure

    ***************************************************************************/

    private void verifyGetAllFilter ( DhtClient dht, cstring channel )
    {
        const filter = "0";

        hash_t[] local;
        foreach ( k, v; this.local.data )
        {
            if ( v.contains(filter) )
                local ~= k;
        }

        auto remote = dht.getAllFilter(channel, filter);
        log.trace("\tVerifying channel with GetAllFilter: local:{}, remote:{}",
            local.length, remote.length);
        test!("==")(local.length, remote.length);

        foreach ( k, v; remote )
        {
            test(local.contains(k));
            test!("==")(v, this.local.data[k]);
        }
    }

    /***************************************************************************

        Compares the keys of all records in the DHT channel against the keys of
        records in the local store, using a DHT GetAllKeys request.

        Params:
            dht = DHT client to use to perform tests
            channel = name of channel to compare against in DHT

        Throws:
            TestException upon verification failure

    ***************************************************************************/

    private void verifyGetAllKeys ( DhtClient dht, cstring channel )
    {
        auto remote = dht.getAllKeys(channel);
        log.trace("\tVerifying channel with GetAllKeys: local:{}, remote:{}",
            this.local.data.length, remote.length);
        test!("==")(this.local.data.length, remote.length);

        foreach ( k; remote )
        {
            test!("in")(k, this.local.data);
        }
    }

    /***************************************************************************

        Compares the existence of all records in the DHT channel against the
        existence of records in the local store, using DHT Exists requests.

        Params:
            dht = DHT client to use to perform tests
            channel = name of channel to compare against in DHT

        Throws:
            TestException upon verification failure

    ***************************************************************************/

    private void verifyExists ( DhtClient dht, cstring channel )
    {
        log.trace("\tVerifying channel with Exists");
        foreach ( k, v; this.local.data )
        {
            auto exists = dht.exists(channel, k);
            test(exists);
        }
    }

    /***************************************************************************

        Compares all records in the DHT channel against the records in the local
        store, using DHT Get requests.

        Params:
            dht = DHT client to use to perform tests
            channel = name of channel to compare against in DHT

        Throws:
            TestException upon verification failure

    ***************************************************************************/

    private void verifyGet ( DhtClient dht, cstring channel )
    {
        log.trace("\tVerifying channel with Get");
        foreach ( k, v; this.local.data )
        {
            auto remote_v = dht.get(channel, k);
            test!("==")(remote_v, v);
        }
    }
}


