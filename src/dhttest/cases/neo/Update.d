/*******************************************************************************

    Tests for the neo Update request.

    Copyright:
        Copyright (c) 2018 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.neo.Update;

import ocean.transition;
import ocean.core.Test;
import dhttest.DhtTestCase : NeoDhtTestCase;
import dhtproto.client.DhtClient;

/*******************************************************************************

    Tests that Update does nothing on a non-existent record.

*******************************************************************************/

class NoRecord : NeoDhtTestCase
{
    import ocean.core.SmartUnion;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Update on an empty channel";
        return desc;
    }

    public override void run ( )
    {
        bool record_not_found;

        void notifier ( DhtClient.Neo.Update.Notification info,
            Const!(DhtClient.Neo.Update.Args) args )
        {
            with ( info.Active ) final switch ( info.active )
            {
                case received:
                case succeeded:
                case conflict:
                    break;

                case no_record:
                    record_not_found = true;
                    break;

                case error:
                case no_node:
                case node_disconnected:
                case node_error:
                case wrong_node:
                case unsupported:
                    break;

                mixin(typeof(info).handleInvalidCases);
            }
        }

        hash_t key;
        this.dht.blocking.update(this.test_channel, key, &notifier);
        test(record_not_found);
    }
}

/*******************************************************************************

    Simple test to Put a record, Update it, then Get the updated value.

*******************************************************************************/

class Update : NeoDhtTestCase
{
    import ocean.core.SmartUnion;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Update";
        return desc;
    }

    public override void run ( )
    {
        bool update_succeeded;

        void notifier ( DhtClient.Neo.Update.Notification info,
            Const!(DhtClient.Neo.Update.Args) args )
        {
            with ( info.Active ) final switch ( info.active )
            {
                case received:
                    (*info.received.updated_value) = "hello world".dup;
                    break;

                case succeeded:
                    update_succeeded = true;
                    break;

                case conflict:
                case no_record:
                    break;

                case error:
                case no_node:
                case node_disconnected:
                case node_error:
                case wrong_node:
                case unsupported:
                    break;

                mixin(typeof(info).handleInvalidCases);
            }
        }

        hash_t key;
        auto put_res = this.dht.blocking.put(this.test_channel, key, "hello");
        test(put_res.succeeded);

        this.dht.blocking.update(this.test_channel, key, &notifier);
        test(update_succeeded);

        void[] buf;
        auto get_res = this.dht.blocking.get(this.test_channel, key, buf);
        test(get_res.succeeded);
        test!("==")(get_res.value, "hello world");
    }
}

/*******************************************************************************

    Simple test to Put a record, Update it, then Get the updated value, using
    the serialization methods of the notifier.

*******************************************************************************/

class SerializerUpdate : NeoDhtTestCase
{
    import ocean.core.SmartUnion;
    import ocean.util.serialize.contiguous.Contiguous;
    import ocean.util.serialize.contiguous.Deserializer;
    import ocean.util.serialize.contiguous.Serializer;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Update with serialization";
        return desc;
    }

    public override void run ( )
    {
        struct Record
        {
            mstring name;
            hash_t id;
            ulong[7] daily_totals;
        }

        bool update_succeeded;

        void notifier ( DhtClient.Neo.Update.Notification info,
            Const!(DhtClient.Neo.Update.Args) args )
        {
            with ( info.Active ) final switch ( info.active )
            {
                case received:
                    // Deserialize the record.
                    Contiguous!(Record) record;
                    auto deserialized = info.received.deserialize(record);

                    // Update the record.
                    deserialized.daily_totals[0]++;

                    // Serialize the updated record.
                    info.received.serialize(*deserialized);
                    break;

                case succeeded:
                    update_succeeded = true;
                    break;

                case conflict:
                case no_record:
                    break;

                case error:
                case no_node:
                case node_disconnected:
                case node_error:
                case wrong_node:
                case unsupported:
                    break;

                mixin(typeof(info).handleInvalidCases);
            }
        }

        Record r;
        r.name = "hello".dup;
        r.id = 23;
        r.daily_totals[0] = 1;
        void[] buf;
        Serializer.serialize(r, buf);

        hash_t key;
        auto put_res = this.dht.blocking.put(this.test_channel, key, buf);
        test(put_res.succeeded);

        this.dht.blocking.update(this.test_channel, key, &notifier);
        test(update_succeeded);

        auto get_res = this.dht.blocking.get(this.test_channel, key, buf);
        test(get_res.succeeded);
        Contiguous!(Record) c;
        auto r2 = Deserializer.deserialize(buf, c).ptr;
        test!("==")(r2.name, r.name);
        test!("==")(r2.id, r.id);
        test!("==")(r2.daily_totals[0], 2);
    }
}
