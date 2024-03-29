/*******************************************************************************

    Test channel serializer.

    Copyright:
        Copyright (c) 2019 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module integrationtest.channelserializer.main;

import dhtproto.client.helper.ChannelSerializer;

import ocean.meta.types.Qualifiers;
import ocean.core.Test;
import ocean.core.DeepCompare;
import ocean.util.serialize.contiguous.Contiguous;
import ocean.util.serialize.contiguous.Deserializer;
import ocean.util.serialize.contiguous.Serializer;
import ocean.util.test.DirectorySandbox;
import ocean.util.container.map.HashMap;
import Path = ocean.io.Path;

version ( unittest ) { }
else
int main ( string[] args )
{
    struct S
    {
        int i;
        bool b;
        cstring str;
    }

    auto test_dir = DirectorySandbox.create(["ChannelSerializer"]);
    scope (exit) test_dir.remove();

    auto s1_init = S(23, true, "hello");
    auto s2_init = S(42, false, "bonjour");
    Contiguous!(S) s1, s2;
    void[] ser_buf;
    Deserializer.deserialize(Serializer.serialize(s1_init, ser_buf), s1);
    Deserializer.deserialize(Serializer.serialize(s2_init, ser_buf), s2);

    // AA dump / load test
    {
        auto ser = new ChannelSerializer!(S)("test_channel");
        Contiguous!(S)[hash_t] out_aa;
        out_aa[0] = s1;
        out_aa[1] = s2;
        ser.dump(out_aa, true);
        test(Path.exists("test_channel"));

        Contiguous!(S)[hash_t] in_aa;
        ser.load(in_aa);
        test!("==")(in_aa.length, 2);
        test(deepEquals(*(in_aa[0].ptr), *(s1.ptr)));
        test(deepEquals(*(in_aa[1].ptr), *(s2.ptr)));
        test!("!=")(in_aa[0].ptr.str.ptr, s1.ptr.str.ptr);
        test!("!=")(in_aa[1].ptr.str.ptr, s2.ptr.str.ptr);
    }

    // Map dump / load test
    {
        auto ser = new ChannelSerializer!(S)("test_channel");
        auto map = new HashMap!(Contiguous!(S))(10);
        *map.put(0) = s1;
        *map.put(1) = s2;
        ser.dump(map, true);
        test(Path.exists("test_channel"));

        map.clear();
        ser.load(map);
        test!("==")(map.length, 2);
        test(deepEquals(*(map[0].ptr), *(s1.ptr)));
        test(deepEquals(*(map[1].ptr), *(s2.ptr)));
        test!("!=")(map[0].ptr.str.ptr, s1.ptr.str.ptr);
        test!("!=")(map[1].ptr.str.ptr, s2.ptr.str.ptr);
    }

    // Broken dump test
    {
        auto ser = new ChannelSerializer!(S)("failed_channel");

        void dumpRecord ( scope void delegate ( hash_t, ref Contiguous!(S) ) record_dg )
        {
            throw new Exception("File write error");
        }

        testThrown!()(ser.dump(&dumpRecord, true));
        test(!Path.exists("failed_channel"));
    }

    return 0;
}
