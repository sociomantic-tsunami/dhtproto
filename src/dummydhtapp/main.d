/*******************************************************************************

    Infinitely running binary used as dummy tested application in dhtproto own
    tests.

    It keeps listening on channel 'test_channel1' and writing new records to
    'test_channel2'.

    It should be never used for any other purpose.

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dummydhtapp.main;

/*******************************************************************************

    Imports

*******************************************************************************/

import core.thread;
import core.stdc.stdlib : abort;

import ocean.transition;
import ocean.io.Stdout;
import ocean.core.Time;

import ocean.net.server.unix.UnixListener;

import ocean.io.select.client.FiberSelectEvent;
import ocean.io.select.client.FiberTimerEvent;
import ocean.io.select.EpollSelectDispatcher;
import ocean.io.select.fiber.SelectFiber;

import swarm.client.helper.NodesConfigReader;
import swarm.client.plugins.ScopeRequests;
import swarm.util.Hash;
import dhtproto.client.DhtClient;

/*******************************************************************************

    Globals

*******************************************************************************/

alias ExtensibleDhtClient!(ScopeRequestsPlugin) DhtClient;

EpollSelectDispatcher epoll;
SelectFiber           fiber;
FiberSelectEvent      event;
DhtClient             dht;

/*******************************************************************************

    Entry point. Creates all globals, performs handshake and starts
    infinite Listen request.

*******************************************************************************/

version ( UnitTest ) {}
else
void main ( istring[] args )
{
    if (args.length > 1 && args[1] == "--message")
    {
        // special path used in CLI mode example
        Stdout.formatln("Test Message").flush();
        return;
    }

    void handshakeAndRegister ( )
    {
        auto timer = new FiberTimerEvent(fiber);
        bool all_ok;

        void handshake ( DhtClient.RequestContext, bool ok )
        {
            all_ok &= ok;
            event.trigger();
        }

        do
        {
            dht = new DhtClient(epoll, new ScopeRequestsPlugin, 2);
            all_ok = true;

            dht.addNodes("./etc/dht.nodes");
            dht.nodeHandshake(&handshake, null);

            event.wait();

            if (!all_ok)
                timer.wait(3.0);
        }
        while (!all_ok);

        Stdout.formatln("Starting Listen request").flush();
        (new Sync("test_channel1", "test_channel2")).register();
    }

    epoll = new EpollSelectDispatcher;
    fiber = new SelectFiber(epoll, &handshakeAndRegister, 256 * 1024);
    event = new FiberSelectEvent(fiber);

    void ping_handler ( cstring args, void delegate ( cstring
        response ) send_response )
    {
        send_response("pong " ~ args);
    }

    void reset_handler ( cstring args, void delegate ( cstring
        response ) send_response )
    {
        send_response("ACK");
    }

    auto un_listener = new UnixListener(
        "turtle.socket",
        epoll,
        [ "ping"[] : &ping_handler, "reset" : &reset_handler ]
    );

    epoll.register(un_listener);

    fiber.start();
    epoll.eventLoop();
}

/*******************************************************************************

    Class that captures key/value to eventually put into
    target channel.

*******************************************************************************/

class Putter
{
    cstring channel, value;
    hash_t key;

    this ( cstring channel, hash_t key, cstring value )
    {
        this.channel = channel.dup;
        this.key = key;
        this.value = value.dup;
    }

    void notify ( DhtClient.RequestNotification info )
    {
        if (info.type == info.type.Finished && !info.succeeded)
        {
            Stderr.formatln("ABORT: Put failure ({})", info.exception).flush();
            abort();
        }
    }

    cstring input ( DhtClient.RequestContext context )
    {
        return this.value;
    }

    void register ( )
    {

        dht.assign(dht.put(this.channel, this.key, &this.input, &this.notify));
    }
}

/*******************************************************************************

    Initiates Listen request on channel `src` that writes all records
    to channel `dst`.

*******************************************************************************/

class Sync
{
    cstring src;
    cstring dst;

    this ( cstring src, cstring dst )
    {
        this.src = src;
        this.dst = dst;
    }

    void record ( DhtClient.RequestContext c, in cstring key,
        in cstring value )
    {
        Stdout.formatln("Syncing '{}'='{}'", key, value).flush();
        HexDigest hash; hash[] = key[];
        (new Putter(this.dst, swarm.util.Hash.toHash(hash), value)).register();
    }

    void notify ( DhtClient.RequestNotification info )
    {
        if (info.type == info.type.Finished && !info.succeeded)
        {
            // some tests use node restart functionality - to make this simple
            // app compatible with them, listen request needs to be restarted
            // upon failures until the app gets killed
            Stderr.formatln("Listen failure, trying again in 100 ms").flush();
            Thread.sleep(seconds(0.1));
            (new Sync(this.src, this.dst)).register();
        }
    }

    void register ( )
    {
        Stdout.formatln("Starting sync from {} to {}", this.src, this.dst).flush();
        dht.assign(dht.listen(this.src, &this.record, &this.notify));
    }
}
