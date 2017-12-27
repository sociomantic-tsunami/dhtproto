/*******************************************************************************

    Contains set of very simple test cases for basic DHT commands

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.neo.Basic;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhttest.DhtTestCase : NeoDhtTestCase;

/*******************************************************************************

    Checks that data stored in DHT can be retrievied back with neo Put/Get.

*******************************************************************************/

class PutGet : NeoDhtTestCase
{
    override public Description description ( )
    {
        Description desc;
        desc.priority = 100;
        desc.name = "Neo Put followed by neo Get";
        return desc;
    }

    public override void run ( )
    {
        cstring[hash_t] payloads = [ 0xA:"foo", 0xB:"bar", 0xC:"doo" ];

        foreach (key, val; payloads)
        {
            auto res = this.dht.blocking.put(this.test_channel, key, val);
            test(res.succeeded);
        }

        void[] buf;
        foreach (key, val; payloads)
        {
            auto res = this.dht.blocking.get(this.test_channel, key, buf);
            test(res.succeeded);
            test!("==")(val, cast(mstring)res.value);
        }
    }
}

/*******************************************************************************

    Checks that data stored in DHT can be removed with neo Remove.

*******************************************************************************/

class PutRemoveGet : NeoDhtTestCase
{
    override public Description description ( )
    {
        Description desc;
        desc.priority = 100;
        desc.name = "Neo Put followed by neo Remove and neo Get";
        return desc;
    }

    public override void run ( )
    {
        auto put_res = this.dht.blocking.put(this.test_channel, 0, "test");
        test(put_res.succeeded);

        auto rem_res = this.dht.blocking.remove(this.test_channel, 0);
        test(rem_res.succeeded);
        test(rem_res.existed);

        void[] buf;
        auto get_res = this.dht.blocking.get(this.test_channel, 0, buf);
        test(get_res.succeeded);
        test!("is")(get_res.value, null);
    }
}

/*******************************************************************************

    Checks that data stored in other test cases is not persistent - and that
    it doesn't magically appear from nowhere.

*******************************************************************************/

class GetNonExistent : NeoDhtTestCase
{
    override public Description description ( )
    {
        Description desc;
        desc.priority = 100;
        desc.name = "Neo Get for non-existent entry";
        return desc;
    }

    public override void run ( )
    {
        void[] buf;
        auto res = this.dht.blocking.get(this.test_channel, 0xA, buf);
        test(res.succeeded);
        test!("is")(res.value, null);
    }
}
