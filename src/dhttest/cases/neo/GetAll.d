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

import ocean.transition;
import ocean.core.Test;
import dhttest.DhtTestCase : NeoDhtTestCase;
import dhtproto.client.DhtClient;

/*******************************************************************************

    Test case which starts a GetAll then suspends and resumes it.

*******************************************************************************/

public class GetAllSuspend : NeoDhtTestCase
{
    import ocean.task.Task;
    import ocean.io.select.client.TimerEvent;
    import ocean.math.random.Random;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Puts followed by neo GetAll and suspend/resume";
        return desc;
    }

    public override void run ( )
    {
        auto task = Task.getThis();
        auto rand = new Random;

        const num_records = 1000;
        ubyte[] val;
        val.length = 8 * 1024;
        for ( hash_t key = 0; key < num_records; key++ )
        {
            foreach ( ref b; val )
                b = rand.uniform!(ubyte)();

            auto res = this.dht.blocking.put(this.test_channel, key, val);
            test(res.succeeded);
        }

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
                DhtClient.Neo.GetAll.Args args )
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
        DhtClient.Neo.GetAll.Notifier user_notifier )
    in
    {
        assert(this.user_notifier is null);
    }
    out
    {
        assert(this.user_notifier !is null);
    }
    body
    {
        this.user_notifier = user_notifier;
        this.id = this.dht.neo.getAll(channel, &this.counterNotifier);
    }

    /***************************************************************************

        Suspends the GetAll request, using the controller to send a message to
        the node. When the request is suspended, the GetAll notifier will be
        called.

    ***************************************************************************/

    public void suspend ( )
    in
    {
        assert(this.id != this.id.init);
    }
    body
    {
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
    in
    {
        assert(this.id != this.id.init);
    }
    body
    {
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
    in
    {
        assert(this.id != this.id.init);
    }
    body
    {
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
        DhtClient.Neo.GetAll.Args args )
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
