/*******************************************************************************

    Test cases for the neo GetAll request.

    Note that the basic behaviour of the GetAll request is tested in the
    NeoVerifier, where it's used to check the results of Put tests.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.neo.GetAll;

import ocean.meta.types.Qualifiers;
import ocean.core.Test;
import ocean.core.Verify;
import ocean.math.random.Random;
import dhttest.DhtTestCase : NeoDhtTestCase;
import dhtproto.client.DhtClient;

/*******************************************************************************

    Test case for Task-blocking GetAll.

*******************************************************************************/

public class GetAllBlocking : NeoDhtTestCase
{
    import ocean.task.Task;
    import ocean.io.select.client.TimerEvent;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Puts followed by Task-blocking neo GetAll";
        return desc;
    }

    public override void run ( )
    {
        auto task = Task.getThis();

        static immutable num_records = 1000;
        putRecords(this.dht, this.test_channel, num_records);

        void[] buf;
        void[][hash_t] received;
        bool duplicate;
        foreach ( k, v; this.dht.blocking.getAll(this.test_channel, buf) )
        {
            if ( k in received )
                duplicate = true;
            received[k] = v.dup;
        }

        test!("==")(received.length, num_records);
        test(!duplicate);
        for ( hash_t key = 0; key < num_records; key++ )
            test!("in")(key, received);
    }
}

/*******************************************************************************

    Test case which starts a GetAll then suspends and resumes it.

*******************************************************************************/

public class GetAllSuspend : NeoDhtTestCase
{
    import ocean.task.Task;
    import ocean.task.Scheduler;
    import ocean.io.select.client.TimerEvent;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Puts followed by neo GetAll and suspend/resume";
        return desc;
    }

    public override void run ( )
    {
        auto task = Task.getThis();

        static immutable num_records = 1000;
        putRecords(this.dht, this.test_channel, num_records);

        auto getall = GetAll(this.dht);

        // Timer which resumes the request.
        scope resume_timer = new TimerEvent(
            {
                getall.resume();
                return false;
            }
        );

        uint suspend_count;

        getall.start(this.test_channel,
            ( DhtClient.Neo.GetAll.Notification info,
                const(DhtClient.Neo.GetAll.Args) args )
            {
                with ( info.Active ) switch ( info.active )
                {
                    case started:
                        // As soon as the GetAll is up, suspend
                        getall.suspend();
                        break;

                    case suspended:
                        suspend_count++;

                        // When suspended, register the timer to resume in a bit.
                        resume_timer.set(0, 500, 0, 0);
                        theScheduler.epoll.register(resume_timer);
                        break;

                    case resumed:
                        break;

                    case finished:
                        task.resume();
                        break;

                    default:
                        break;
                }
            }
        );

        scope ( exit ) theScheduler.epoll.unregister(resume_timer);

        task.suspend();
        test!("==")(getall.received_keys.length, num_records);
        test(!getall.duplicate);
        test!("==")(suspend_count, 1);
    }
}

/*******************************************************************************

    Test case which starts a GetAll then kills all connections and checks that
    the GetAll request successfully reconnects and continues.

*******************************************************************************/

public class GetAllConnError : NeoDhtTestCase
{
    import turtle.env.ControlSocket : sendCommand;
    import ocean.task.Task;
    import ocean.io.select.client.TimerEvent;
    import swarm.neo.client.requests.NotificationFormatter;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Puts followed by neo GetAll with connection drop";
        return desc;
    }

    public override void run ( )
    {
        auto task = Task.getThis();

        static immutable num_records = 1000;
        putRecords(this.dht, this.test_channel, num_records);

        uint disconnection_count;
        auto getall = GetAll(this.dht);
        getall.start(this.test_channel,
            ( DhtClient.Neo.GetAll.Notification info,
                const(DhtClient.Neo.GetAll.Args) args )
            {
                with ( info.Active ) switch ( info.active )
                {
                    case received:
                        if ( getall.received_keys.length == num_records / 2 )
                            this.dht.neo.reconnect();
                        break;

                    case node_disconnected:
                        disconnection_count++;
                        break;

                    case finished:
                        task.resume();
                        break;

                    default:
                        break;
                }
            }
        );

        task.suspend();
        test!("==")(getall.received_keys.length, num_records);
        test(!getall.duplicate);
        test!("==")(disconnection_count, 1);
    }
}

/*******************************************************************************

    Helper function to write some records to the specified channel. Random 8K
    record values are written.

    Params:
        dht = DHT client instance to perform Puts with
        channel = channel to write to
        num_records = the number of records to write. Records are written with
            keys from 0..num_records

*******************************************************************************/

private void putRecords ( DhtClient dht, cstring channel, size_t num_records )
{
    auto rand = new Random;

    ubyte[] val;
    val.length = 8 * 1024;
    for ( hash_t key = 0; key < num_records; key++ )
    {
        foreach ( ref b; val )
            b = rand.uniform!(ubyte)();

        auto res = dht.blocking.put(channel, key, val);
        test(res.succeeded);
    }
}

/*******************************************************************************

    Helper for performing a GetAll request and checking the results. Reduces the
    amount of boiler-plate in each test case.

*******************************************************************************/

private struct GetAll
{
    import swarm.neo.protocol.Message : RequestId;

    /// DHT client to start GetAll request with.
    private DhtClient dht;

    /// GetAll request id.
    public RequestId id;

    /// Set of keys received.
    public bool[hash_t] received_keys;

    /// Flag set when a key is received twice by the request (an error).
    public bool duplicate;

    /// User-provided GetAll notifier, passed to start().
    private DhtClient.Neo.GetAll.Notifier user_notifier;

    /***************************************************************************

        Starts the GetAll request on the specified channel with the specified
        settings.

        Params:
            channel = channel to getall
            user_notifier = GetAll notifier (must be non-null)

    ***************************************************************************/

    public void start ( cstring channel,
        scope DhtClient.Neo.GetAll.Notifier user_notifier )
    out
    {
        assert(this.user_notifier !is null);
    }
    do
    {
        verify(this.user_notifier is null);
        this.user_notifier = user_notifier;
        this.id = this.dht.neo.getAll(channel, &this.counterNotifier);
    }

    /***************************************************************************

        Suspends the GetAll request, using the controller to send a message to
        the node. When the request is suspended, the GetAll notifier will be
        called.

    ***************************************************************************/

    public void suspend ( )
    {
        verify(this.id != this.id.init);
        this.dht.neo.control(this.id,
            ( DhtClient.Neo.GetAll.IController getall )
            {
                getall.suspend();
            }
        );
    }

    /***************************************************************************

        Resumes the GetAll request, using the controller to send a message to
        the node. When the request is resumed, the GetAll notifier will be
        called.

    ***************************************************************************/

    public void resume ( )
    {
        verify(this.id != this.id.init);
        this.dht.neo.control(this.id,
            ( DhtClient.Neo.GetAll.IController getall )
            {
                getall.resume();
            }
        );
    }

    /***************************************************************************

        Stops the GetAll request, using the controller to send a message to the
        node. When the request has finished, the GetAll notifier will be called.

    ***************************************************************************/

    public void stop ( )
    {
        verify(this.id != this.id.init);
        this.dht.neo.control(this.id,
            ( DhtClient.Neo.GetAll.IController getall )
            {
                getall.stop();
            }
        );
    }

    /***************************************************************************

        Internal GetAll notifier. Updates the counters and calls the user's
        notifier.

        Params:
            info = GetAll notification
            args = request arguments

    ***************************************************************************/

    private void counterNotifier ( DhtClient.Neo.GetAll.Notification info,
        const(DhtClient.Neo.GetAll.Args) args )
    {
        with ( info.Active ) switch ( info.active )
        {
            case received:
                if ( info.received.key in this.received_keys )
                    this.duplicate = true;
                this.received_keys[info.received.key] = true;
                break;

            default:
                break;
        }

        this.user_notifier(info, args);
    }
}
