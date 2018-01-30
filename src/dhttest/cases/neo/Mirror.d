/*******************************************************************************

    Test cases for the neo Mirror request.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.neo.Mirror;

import ocean.transition;
import ocean.core.Test;
import dhttest.DhtTestCase : NeoDhtTestCase;
import dhtproto.client.DhtClient;

/*******************************************************************************

    Test case which writes some records to the test channel, starts an updating
    mirror, then removes some records.

*******************************************************************************/

public class MirrorRemove : NeoDhtTestCase
{
    import ocean.task.Task;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Put followed by neo Mirror + Removes";
        return desc;
    }

    public override void run ( )
    {
        this.legacyConnect(10000);

        auto task = Task.getThis();

        putRecords(this.dht, this.test_channel, 100);

        DhtClient.Neo.Mirror.Settings mirror_settings;
        mirror_settings.initial_refresh = false;
        mirror_settings.periodic_refresh_s = 0;

        void delNotifier ( DhtClient.RequestNotification info ) { }

        const end_after_deletions = 5;
        auto mirror = Mirror(this.dht);
        mirror.start(mirror_settings, this.test_channel,
            ( DhtClient.Neo.Mirror.Notification info,
                Const!(DhtClient.Neo.Mirror.Args) args )
            {
                with ( info.Active ) switch ( info.active )
                {
                    case started:
                        // As soon as the mirror is up, delete some records
                        for ( hash_t del_key = 0; del_key < end_after_deletions;
                            del_key++ )
                        {
                            this.dht.assign(
                                this.dht.remove(this.test_channel, del_key,
                                    &delNotifier));
                        }
                        break;

                    case deleted:
                        // Stop mirroring after the records have been deleted
                        if ( mirror.deleted_count == end_after_deletions )
                            mirror.stop();
                        break;

                    case stopped:
                        task.resume();
                        break;

                    default:
                        break;
                }
            }
        );

        task.suspend();
        test!("==")(mirror.updated_count, 0);
        test!("==")(mirror.refreshed_count, 0);
        test!("==")(mirror.deleted_count, end_after_deletions);
    }
}

/*******************************************************************************

    Test case which starts an updating mirror then writes some records.

*******************************************************************************/

public class MirrorUpdate : NeoDhtTestCase
{
    import ocean.task.Task;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Mirror followed by neo Puts";
        return desc;
    }

    public override void run ( )
    {
        auto task = Task.getThis();

        DhtClient.Neo.Mirror.Settings mirror_settings;
        mirror_settings.initial_refresh = false;
        mirror_settings.periodic_refresh_s = 0;

        void putNotifier ( DhtClient.Neo.Put.Notification info,
            Const!(DhtClient.Neo.Put.Args) args ) { }

        const num_written = 100;
        auto mirror = Mirror(this.dht);
        mirror.start(mirror_settings, this.test_channel,
            ( DhtClient.Neo.Mirror.Notification info,
                Const!(DhtClient.Neo.Mirror.Args) args )
            {
                with ( info.Active ) switch ( info.active )
                {
                    case started:
                        // As soon as the mirror is up, put some records
                        putRecords(this.dht, this.test_channel, num_written,
                            &putNotifier);
                        break;

                    case updated:
                        // Stop mirroring after the updates have been received
                        if ( mirror.updated_count == num_written )
                            mirror.stop();
                        break;

                    case stopped:
                        task.resume();
                        break;

                    default:
                        break;
                }
            }
        );

        task.suspend();
        test!("==")(mirror.updated_count, num_written);
        test!("==")(mirror.refreshed_count, 0);
        test!("==")(mirror.deleted_count, 0);
    }
}

/*******************************************************************************

    Test case which writes some records, starts a Mirror, waits for the first
    refresh cycle to complete (returning all records to the client), then kills
    all connections and checks that the Mirror request successfully reconnects
    and performs a second refresh cycle.

*******************************************************************************/

public class MirrorConnError : NeoDhtTestCase
{
    import ocean.task.Task;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Puts followed by neo Mirror with connection drop";
        return desc;
    }

    public override void run ( )
    {
        auto task = Task.getThis();

        const num_written = 100;
        putRecords(this.dht, this.test_channel, num_written);

        DhtClient.Neo.Mirror.Settings mirror_settings;
        mirror_settings.initial_refresh = true;
        mirror_settings.periodic_refresh_s = 0;

        uint disconnection_count;
        auto mirror = Mirror(this.dht);
        mirror.start(mirror_settings, this.test_channel,
            ( DhtClient.Neo.Mirror.Notification info,
                Const!(DhtClient.Neo.Mirror.Args) args )
            {
                with ( info.Active ) switch ( info.active )
                {
                    case started:
                        break;

                    case refreshed:
                        // After the first refresh is complete, tell the client
                        // to drop and re-establish all connections.
                        if ( mirror.refreshed_count == num_written )
                            this.dht.neo.reconnect();

                        // After the second refresh is complete, stop the
                        // request.
                        if ( mirror.refreshed_count == num_written * 2 )
                            mirror.stop();
                        break;

                    case node_disconnected:
                        disconnection_count++;
                        break;

                    case stopped:
                        task.resume();
                        break;

                    default:
                        break;
                }
            }
        );

        task.suspend();
        test!("==")(mirror.updated_count, 0);
        test!("==")(mirror.refreshed_count, num_written * 2);
        test!("==")(mirror.deleted_count, 0);
        test!("==")(disconnection_count, 1);
    }
}

/*******************************************************************************

    Test case which starts an updating mirror then writes some records while
    periodically suspending and resuming the request.

*******************************************************************************/

public class MirrorSuspend : NeoDhtTestCase
{
    import ocean.task.Task;
    import ocean.io.select.client.TimerEvent;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Mirror followed by neo Puts and suspend/resume";
        return desc;
    }

    public override void run ( )
    {
        auto task = Task.getThis();

        DhtClient.Neo.Mirror.Settings mirror_settings;
        mirror_settings.initial_refresh = false;
        mirror_settings.periodic_refresh_s = 0;

        const end_after_updates = 1_000;
        size_t num_written;
        auto mirror = Mirror(this.dht);

        // Timer which resumes the request.
        scope resume_timer = new TimerEvent(
            {
                mirror.resume();
                return false;
            }
        );

        // Timer which puts every 1ms
        hash_t key;
        ubyte[] value;
        value.length = 16 * 1024;
        scope put_timer = new TimerEvent(
            {
                if ( num_written < end_after_updates )
                {
                    this.dht.neo.put(this.test_channel, key++, value,
                        ( DhtClient.Neo.Put.Notification info,
                            Const!(DhtClient.Neo.Put.Args) args )
                        {
                            if ( info.active == info.active.success )
                                num_written++;
                        }
                    );
                }
                return num_written < end_after_updates;
            }
        );
        put_timer.set(0, 1, 0, 1);

        bool[hash_t] received_keys;
        uint suspend_count;
        bool duplicate;

        mirror.start(mirror_settings, this.test_channel,
            ( DhtClient.Neo.Mirror.Notification info,
                Const!(DhtClient.Neo.Mirror.Args) args )
            {
                with ( info.Active ) switch ( info.active )
                {
                    case started:
                        // As soon as the mirror is up, start the Put timer and
                        // suspend.
                        theScheduler.epoll.register(put_timer);
                        mirror.suspend();
                        break;

                    case updated:
                        if ( info.updated.key in received_keys )
                            duplicate = true;

                        received_keys[info.updated.key] = true;
                        // Stop mirroring after the updates have been received
                        if ( mirror.updated_count == end_after_updates )
                            mirror.stop();
                        break;

                    case suspended:
                        suspend_count++;

                        // When suspended, register the timer to resume in a bit.
                        resume_timer.set(0, 500, 0, 0);
                        theScheduler.epoll.register(resume_timer);
                        break;

                    case stopped:
                        task.resume();
                        break;

                    default:
                        break;
                }
            }
        );

        scope ( exit ) theScheduler.epoll.unregister(resume_timer);
        scope ( exit ) theScheduler.epoll.unregister(put_timer);

        task.suspend();
        test(!duplicate);
        foreach ( k; received_keys )
            test!("<")(k, num_written);
        test!("==")(suspend_count, 1);
        test!("==")(mirror.updated_count, num_written);
        test!("==")(mirror.refreshed_count, 0);
        test!("==")(mirror.deleted_count, 0);
    }
}

/*******************************************************************************

    Test case which writes some records and starts a periodically refreshing
    mirror.

*******************************************************************************/

public class MirrorRefresh : NeoDhtTestCase
{
    import ocean.task.Task;
    import ocean.io.select.client.TimerEvent;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Put followed by refreshing Mirror";
        return desc;
    }

    public override void run ( )
    {
        auto task = Task.getThis();

        DhtClient.Neo.Mirror.Settings mirror_settings;
        mirror_settings.initial_refresh = false;
        mirror_settings.periodic_refresh_s = 1;

        const num_written = 1_000;
        putRecords(this.dht, this.test_channel, num_written);

        const end_after_refreshes = num_written * 3;
        auto mirror = Mirror(this.dht);
        mirror.start(mirror_settings, this.test_channel,
            ( DhtClient.Neo.Mirror.Notification info,
                Const!(DhtClient.Neo.Mirror.Args) args )
            {
                with ( info.Active ) switch ( info.active )
                {
                    case refreshed:
                        // Stop mirroring after the updates have been received
                        if ( mirror.refreshed_count == end_after_refreshes )
                            mirror.stop();
                        break;

                    case stopped:
                        task.resume();
                        break;

                    default:
                        break;
                }
            }
        );

        task.suspend();
        test!("==")(mirror.updated_count, 0);
        test!("==")(mirror.refreshed_count, end_after_refreshes);
        test!("==")(mirror.deleted_count, 0);
    }
}

/*******************************************************************************

    Test case which writes some records, starts a periodically refreshing
    mirror while periodically suspending and resuming the request.

*******************************************************************************/

public class MirrorRefreshSuspend : NeoDhtTestCase
{
    import ocean.task.Task;
    import ocean.io.select.client.TimerEvent;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Put followed by refreshing Mirror and suspends/resumes";
        return desc;
    }

    public override void run ( )
    {
        auto task = Task.getThis();

        DhtClient.Neo.Mirror.Settings mirror_settings;
        mirror_settings.initial_refresh = false;
        mirror_settings.periodic_refresh_s = 1;

        const num_written = 500;
        putRecords(this.dht, this.test_channel, num_written);

        auto mirror = Mirror(this.dht);

        // Timer which fires once and resumes the Mirror
        scope resume_timer = new TimerEvent(
            {
                mirror.resume();
                return false;
            }
        );

        bool mirror_suspended;
        const end_after_refreshes = num_written * 3;
        bool received_while_suspended;
        mirror.start(mirror_settings, this.test_channel,
            ( DhtClient.Neo.Mirror.Notification info,
                Const!(DhtClient.Neo.Mirror.Args) args )
            {
                with ( info.Active ) switch ( info.active )
                {
                    case started:
                        // As soon as the request starts, suspend it
                        mirror.suspend();
                        break;

                    case refreshed:
                        if ( mirror_suspended )
                            received_while_suspended = true;

                        // Stop mirroring after the updates have been received
                        if ( mirror.refreshed_count == end_after_refreshes )
                            mirror.stop();
                        break;

                    case suspended:
                        mirror_suspended = true;

                        // Set a timer to resume after 2.5s
                        resume_timer.set(2, 500, 0, 0);
                        theScheduler.epoll.register(resume_timer);
                        break;

                    case resumed:
                        mirror_suspended = false;
                        break;

                    case stopped:
                        task.resume();
                        break;

                    default:
                        break;
                }
            }
        );

        scope ( exit ) theScheduler.epoll.unregister(resume_timer);

        task.suspend();
        test(!received_while_suspended);
        test!("==")(mirror.updated_count, 0);
        test!("==")(mirror.refreshed_count, end_after_refreshes);
        test!("==")(mirror.deleted_count, 0);
    }
}

/*******************************************************************************

    Test case which starts an updating mirror then removes the channel.

*******************************************************************************/

public class MirrorRemoveChannel : NeoDhtTestCase
{
    import ocean.task.Task;

    override public Description description ( )
    {
        Description desc;
        desc.name = "Neo Mirror followed by RemoveChannel";
        return desc;
    }

    public override void run ( )
    {
        this.legacyConnect(10000);

        auto task = Task.getThis();

        DhtClient.Neo.Mirror.Settings mirror_settings;
        mirror_settings.initial_refresh = false;
        mirror_settings.periodic_refresh_s = 0;

        void putNotifier ( DhtClient.Neo.Put.Notification info,
            Const!(DhtClient.Neo.Put.Args) args ) { }

        void delNotifier ( DhtClient.RequestNotification info ) { }

        auto mirror = Mirror(this.dht);
        mirror.start(mirror_settings, this.test_channel,
            ( DhtClient.Neo.Mirror.Notification info,
                Const!(DhtClient.Neo.Mirror.Args) args )
            {
                with ( info.Active ) switch ( info.active )
                {
                    case started:
                        // As soon as the mirror is up, remove the channel
                        this.dht.assign(
                            this.dht.removeChannel(this.test_channel,
                                &delNotifier));
                        break;

                    case channel_removed:
                        task.resume();
                        break;

                    default:
                        break;
                }
            }
        );

        task.suspend();
        test!("==")(mirror.updated_count, 0);
        test!("==")(mirror.refreshed_count, 0);
        test!("==")(mirror.deleted_count, 0);
    }
}

/*******************************************************************************

    Helper function to write some records to the specified channel.

    Params:
        dht = DHT client instance to perform Puts with
        channel = channel to write to
        num_records = the number of records to write. Records are written with
            keys from 0..num_records
        notifier = neo Put notifier. If null, blocking Puts are performed

*******************************************************************************/

private void putRecords ( DhtClient dht, cstring channel, size_t num_records,
    DhtClient.Neo.Put.Notifier notifier = null )
{
    ubyte[] val;
    val.length = 128;
    for ( hash_t key = 0; key < num_records; key++ )
    {
        if ( notifier is null )
        {
            auto res = dht.blocking.put(channel, key, val);
            test(res.succeeded);
        }
        else
        {
            dht.neo.put(channel, key, val, notifier);
        }
    }
}

/*******************************************************************************

    Helper for performing a Mirror request and checking the results. Reduces the
    amount of boiler-plate in each test case.

*******************************************************************************/

private struct Mirror
{
    import swarm.neo.protocol.Message : RequestId;

    /// DHT client to start Mirror request with.
    private DhtClient dht;

    /// Mirror request id.
    public RequestId id;

    /// Counters of Mirror actions.
    public size_t updated_count, refreshed_count, deleted_count;

    /// User-provided Mirror notifier, passed to start().
    private DhtClient.Neo.Mirror.Notifier user_notifier;

    /***************************************************************************

        Starts the Mirror request on the specified channel with the specified
        settings.

        Params:
            mirror_settings = settings for Mirror request
            channel = channel to mirror
            user_notifier = Mirror notifier (must be non-null)

    ***************************************************************************/

    public void start ( DhtClient.Neo.Mirror.Settings mirror_settings,
        cstring channel, DhtClient.Neo.Mirror.Notifier user_notifier )
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
        this.id = this.dht.neo.mirror(channel, &this.counterNotifier,
            mirror_settings);
    }

    /***************************************************************************

        Suspends the Mirror request, using the controller to send a message to
        the node. When the request is suspended, the Mirror notifier will be
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
            ( DhtClient.Neo.Mirror.IController mirror )
            {
                mirror.suspend();
            }
        );
    }

    /***************************************************************************

        Resumes the Mirror request, using the controller to send a message to
        the node. When the request is resumed, the Mirror notifier will be
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
            ( DhtClient.Neo.Mirror.IController mirror )
            {
                mirror.resume();
            }
        );
    }

    /***************************************************************************

        Stops the Mirror request, using the controller to send a message to the
        node. When the request has finished, the Mirror notifier will be called.

    ***************************************************************************/

    public void stop ( )
    in
    {
        assert(this.id != this.id.init);
    }
    body
    {
        this.dht.neo.control(this.id,
            ( DhtClient.Neo.Mirror.IController mirror )
            {
                mirror.stop();
            }
        );
    }

    /***************************************************************************

        Internal Mirror notifier. Updates the counters and calls the user's
        notifier.

        Params:
            info = Mirror notification
            args = request arguments

    ***************************************************************************/

    private void counterNotifier ( DhtClient.Neo.Mirror.Notification info,
        Const!(DhtClient.Neo.Mirror.Args) args )
    {
        with ( info.Active ) switch ( info.active )
        {
            case updated:
                this.updated_count++;
                break;

            case refreshed:
                this.refreshed_count++;
                break;

            case deleted:
                this.deleted_count++;
                break;

            default:
                break;
        }

        this.user_notifier(info, args);
    }
}
