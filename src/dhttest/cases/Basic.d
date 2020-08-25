/*******************************************************************************

    Contains set of very simple test cases for basic DHT commands

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.Basic;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.core.Test;
import ocean.meta.types.Qualifiers;
import ocean.core.Test;
import dhttest.DhtTestCase;

static immutable PRIORITY = 100;

/*******************************************************************************

    Checks that data stored in DHT can be retrievied back

*******************************************************************************/

class PutGet : DhtTestCase
{
    override public Description description ( )
    {
        Description desc;
        desc.priority = PRIORITY;
        desc.name = "Put followed by Get";
        return desc;
    }

    public override void run ( )
    {
        cstring[hash_t] payloads = [ 0xA:"foo", 0xB:"bar", 0xC:"doo" ];

        foreach (key, val; payloads)
        {
            this.dht.put(this.test_channel, key, val);
        }

        foreach (key, val; payloads)
        {
            test!("==")(val, this.dht.get(this.test_channel, key));
        }
    }
}

/*******************************************************************************

    Checks that data stored in other test cases is not persistent - and that
    it doesn't magically appear from nowhere.

*******************************************************************************/

class GetNonExistent : DhtTestCase
{
    override public Description description ( )
    {
        Description desc;
        desc.priority = 100;
        desc.name = "Get for non-existent entry";
        return desc;
    }

    public override void run ( )
    {
        test(this.dht.get(this.test_channel, 0xA) is null);
    }
}

/*******************************************************************************

    Checks basic GetAll functionality

*******************************************************************************/

class GetAll : DhtTestCase
{
    override public Description description ( )
    {
        Description desc;
        desc.priority = 100;
        desc.name = "GetAll for predefined data";
        return desc;
    }

    public override void run ( )
    {
        // Put some records to the storage channel.
        string[hash_t] records =
        [
            0x0000000000000000: "record 0",
            0x0000000000000001: "record 1",
            0x0000000000000002: "record 2"
        ];

        foreach (k, v; records)
            this.dht.put(this.test_channel, k, v);

        // Do a GetAll to retrieve them all
        auto fetched = this.dht.getAll(this.test_channel);

        // Confirm the results
        test!("==")(fetched.length, records.length);
        bool[hash_t] checked;
        foreach (k, v; fetched)
        {
            auto r = k in records;
            test(r !is null, "GetAll returned wrong key");
            test(*r == v, "GetAll returned wrong value");
            test(!(k in checked), "GetAll returned the same key twice");
            checked[k] = true;
        }
    }
}

/*******************************************************************************

    Checks that channel gets deleted with all its data

*******************************************************************************/

class RemoveChannel : DhtTestCase
{
    override public Description description ( )
    {
        Description desc;
        desc.priority = 100;
        desc.name = "Removing channel";
        return desc;
    }

    public override void run ( )
    {
        this.dht.put(this.test_channel, 0x1, "1");
        this.dht.removeChannel(this.test_channel);
        test(this.dht.getAll(this.test_channel).length == 0);
    }
}
