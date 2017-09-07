/*******************************************************************************

    Test cases for the neo GetChannels request.

    Note that the basic behaviour of the GetChannels request is tested in the
    NeoVerifier, where it's used to check the results of Put tests.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.neo.GetChannels;

import ocean.transition;
import ocean.core.Test;
import dhttest.DhtTestCase : NeoDhtTestCase;
import dhtproto.client.DhtClient;

/*******************************************************************************

    Basic test case for GetChannels.

*******************************************************************************/

public class GetChannels : NeoDhtTestCase
{
    import ocean.task.Task;
    import ocean.core.array.Search : contains;

    private const channels = ["channel1", "channel2", "channel3", "channel4"];

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Puts followed by neo GetChannels";
        return desc;
    }

    public override void run ( )
    {
        auto task = Task.getThis();

        foreach ( channel; this.channels )
        {
            auto res = this.dht.blocking.put(channel, 0, "whatever");
            test(res.succeeded);
        }

        mstring buf;
        mstring[] received_channels;
        foreach ( channel; dht.blocking.getChannels(buf) )
            received_channels ~= channel.dup;

        test!("==")(this.channels.length, received_channels.length);
        foreach ( channel; this.channels )
            test(received_channels.contains(channel));
    }

    override public void cleanup ( )
    {
        super.cleanup();

        auto legacy_dht = new Legacy.DhtClient;
        legacy_dht.handshake(10000);

        foreach ( channel; this.channels )
            legacy_dht.removeChannel(channel);
    }
}

/*******************************************************************************

    Test case for GetChannels + RemoveChannel.

*******************************************************************************/

public class GetChannelsRemove : NeoDhtTestCase
{
    import ocean.task.Task;
    import ocean.core.array.Search : contains;

    private const channels = ["channel1", "channel2", "channel3", "channel4"];

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Puts followed by legacy RemoveChannel then neo GetChannels";
        return desc;
    }

    public override void run ( )
    {
        auto task = Task.getThis();

        foreach ( channel; this.channels )
        {
            auto res = this.dht.blocking.put(channel, 0, "whatever");
            test(res.succeeded);
        }

        auto legacy_dht = new Legacy.DhtClient;
        legacy_dht.handshake(10000);
        legacy_dht.removeChannel(this.channels[0]);

        mstring buf;
        mstring[] received_channels;
        foreach ( channel; dht.blocking.getChannels(buf) )
            received_channels ~= channel.dup;

        test!("==")(this.channels.length - 1, received_channels.length);
        foreach ( channel; this.channels[1..$] )
            test(received_channels.contains(channel));
    }

    override public void cleanup ( )
    {
        super.cleanup();

        auto legacy_dht = new Legacy.DhtClient;
        legacy_dht.handshake(10000);

        foreach ( channel; this.channels )
            legacy_dht.removeChannel(channel);
    }
}
