/*******************************************************************************

    DHT client usage examples.

    Note that the examples are only for the neo requests.

    High-level module overview:
        1. The standard DHT client in dhtproto.client.DhtClient can communicate
           with the legacy *and* the neo protocols.
        2. The DHT-specific parts of the neo client (e.g. request methods) are
           in dhtproto.client.mixins.NeoSupport.
        3. The generic parts of the neo client (e.g. addNodes()) are in
           swarm.neo.client.mixins.ClientCore.
        4. Each request has an API module that defines its public API (the
           notifier, the arguments, etc). These live in dhtproto.client.request.
        5. The structs returned by the notifiers are in
           swarm.neo.client.NotifierTypes and dhtproto.client.NotifierTypes.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.UsageExamples;


/// Mixin helper for the SmartUnion's final switch handlers. It inserts
/// case none: assert(false); in D2 and default: assert(false); in D1
/// TODO: This should be replaced with the
/// `ocean.core.SmartUnion.handleInvalidCases`, available in ocean v3.5.x and
/// later (not yet released).
const handleInvalidCases = "case none: assert(false);" ~
    // The D2 build makes sure all enum cases are covered so in fact we don't
    // need a default. However, D1 emits a compiler warning if a switch
    // has no default so we add a default here just to avoid the warning.
    "version (D_Version2){} else {default: assert(false);}";

version ( UnitTest )
{
    import ocean.transition;

    import ocean.util.app.DaemonApp;

    // DaemonApp class showing typical neo DHT client initialisation. The class
    // has a single abstract method -- example() -- which is implemented by
    // various usage examples in this module, each demonstrating a different
    // client feature.
    abstract class ExampleApp : DaemonApp
    {
        import ocean.task.Scheduler;
        import ocean.task.Task;
        import ocean.util.log.Logger;
        import ConfigFiller = ocean.util.config.ConfigFiller;
        import ocean.text.convert.Hex : hexToBin;

        import swarm.neo.client.requests.NotificationFormatter;

        import dhtproto.client.DhtClient;

        // DHT client. (See dhtproto.client.DhtClient.)
        private DhtClient dht;

        // Buffer used for message formatting in notifiers.
        private mstring msg_buf;

        // Logger used for logging notifications.
        protected Logger log;

        // Struct encapsulating neo client config options to read from the
        // config file.
        private struct NeoConfig
        {
            // Name of the neo client (used during connection authentication).
            istring auth_name;

            // Key of the neo client (used during connection authentication).
            istring auth_key;
        }

        // Neo config instance to be read from the config file.
        private NeoConfig neo_config;

        // Constructor. Initialises the scheduler.
        public this ( )
        {
            super("example", "DHT client neo usage example", VersionInfo.init);

            // Set up the logger for this example.
            this.log = Log.lookup("example");

            // Initialise the global scheduler.
            SchedulerConfiguration scheduler_config;
            initScheduler(scheduler_config);
        }

        // Reads this.neo_config from the config file.
        override public void processConfig ( IApplication app,
            ConfigParser config )
        {
            ConfigFiller.fill("DHT_Neo", this.neo_config, config);
        }

        // Application run method. Initialises the DHT client and starts the
        // main application task.
        override protected int run ( Arguments args, ConfigParser config )
        {
            // Convert the hex-string auth key read from the config file to the
            // binary (ubyte[]) format required by the neo client.
            ubyte[] auth_key_bin;
            hexToBin(this.neo_config.auth_key, auth_key_bin);

            // Create a DHT client instance, passing the additional
            // arguments required by neo: the authorisation name and key and the
            // connection notifier.
            this.dht = new DhtClient(theScheduler.epoll,
                this.neo_config.auth_name, auth_key_bin, &this.connNotifier);

            // Schedule the application's main task and start the event loop.
            theScheduler.schedule(new AppTask);
            theScheduler.eventLoop();
            return 0;
        }

        // Application main task.
        private class AppTask : Task
        {
            // Task entry point. Waits for the DHT client to connect then runs
            // the example.
            protected override void run ( )
            {
                this.connect();
                this.outer.example();
            }

            // Waits for the DHT client to connect and query the hash ranges of
            // all registered nodes.
            private void connect ( )
            {
                // Add some nodes. (See swarm.neo.client.mixins.ClientCore.)
                // Note: make sure you have a .nodes file which specifies the
                // neo ports of the nodes!
                this.outer.dht.neo.addNodes("dht.nodes");

                // Suspend the task until the hash range of all registered nodes
                // has been queried. (See dhtproto.client.mixins.NeoSupport.)
                this.outer.dht.blocking.waitAllHashRangesKnown();
            }
        }

        // Abstract method containing the logic for each example.
        abstract protected void example ( );

        // Notifier which is called when a connection establishment attempt
        // succeeds or fails and when the hash-range which a connected node is
        // responsible for has been queried. (Also called after re-connection
        // attempts are made.)
        // (See dhtproto.client.mixins.NeoSupport for the definition of the
        // notification union.)
        private void connNotifier ( DhtClient.Neo.DhtConnNotification info )
        {
            formatNotification(info, this.msg_buf);

            with ( info.Active ) final switch ( info.active )
            {
                case connected:
                    this.log.trace(this.msg_buf);
                    break;

                case hash_range_queried:
                case connection_error:
                    this.log.error(this.msg_buf);
                    break;

                mixin(handleInvalidCases);
            }
        }
    }
}

/*******************************************************************************

    Dummy struct to enable ddoc rendering of usage examples.

*******************************************************************************/

struct UsageExamples
{
}

/// Example of neo Put request usage
unittest
{
    class PutExample : ExampleApp
    {
        override protected void example ( )
        {
            // Assign a neo Put request. Note that the channel and value
            // are copied inside the client -- the user does not need to
            // maintain them after calling this method.
            this.dht.neo.put("channel", 0x1234567812345678,
                "value_to_put", &this.putNotifier);
        }

        // Notifier which is called when something of interest happens to
        // the Put request. See dhtproto.client.request.Put for
        // details of the parameters of the notifier.
        private void putNotifier ( DhtClient.Neo.Put.Notification info,
            DhtClient.Neo.Put.Args args )
        {
            formatNotification(info, this.msg_buf);

            with ( info.Active ) final switch ( info.active )
            {
                case success:
                    this.log.trace(this.msg_buf);
                    break;

                case failure:
                case no_node:
                case node_disconnected:
                case node_error:
                case wrong_node:
                case unsupported:
                    this.log.error(this.msg_buf);
                    break;

                mixin(handleInvalidCases);
            }
        }
    }
}

/// Example of Task-blocking neo Put request usage with a notifier
unittest
{
    class PutExample : ExampleApp
    {
        override protected void example ( )
        {
            // Perform a blocking neo Put request. Note that the channel and
            // value are copied inside the client -- the user does not need to
            // maintain them after calling this method.
            this.dht.blocking.put("channel", 0x1234567812345678,
                "value_to_put", &this.putNotifier);
        }

        // Notifier which is called when something of interest happens to
        // the Put request. See dhtproto.client.request.Put for
        // details of the parameters of the notifier.
        private void putNotifier ( DhtClient.Neo.Put.Notification info,
            DhtClient.Neo.Put.Args args )
        {
            formatNotification(info, this.msg_buf);

            with ( info.Active ) final switch ( info.active )
            {
                case success:
                    this.log.trace(this.msg_buf);
                    break;

                case failure:
                case no_node:
                case node_disconnected:
                case node_error:
                case wrong_node:
                case unsupported:
                    this.log.error(this.msg_buf);
                    break;

                mixin(handleInvalidCases);
            }
        }
    }
}

/// Example of simple Task-blocking neo Put request usage without a notifier
unittest
{
    class PutExample : ExampleApp
    {
        override protected void example ( )
        {
            // Perform a blocking neo Put request and return a result struct
            // indicating success/failure. Notes:
            // 1. In a real application, you probably want more information than
            //    just success/failure and should use the task-blocking method
            //    with a notifier (see example above).
            // 2. The channel and value are copied inside the client -- the user
            // does not need to maintain them after calling this method.
            auto result = this.dht.blocking.put("channel", 0x1234567812345678,
                "value_to_put");
            if ( result.succeeded )
                this.log.trace("Put succeeded");
            else
                this.log.error("Put failed");
        }
    }
}

/// Example of neo Get request usage
unittest
{
    class GetExample : ExampleApp
    {
        override protected void example ( )
        {
            // Assign a neo Get request. Note that the channel is copied inside
            // the client -- the user does not need to maintain it after calling
            // this method.
            this.dht.neo.get("channel", 0x1234567812345678, &this.getNotifier);
        }

        // Notifier which is called when something of interest happens to
        // the Get request. See dhtproto.client.request.Get for
        // details of the parameters of the notifier.
        private void getNotifier ( DhtClient.Neo.Get.Notification info,
            DhtClient.Neo.Get.Args args )
        {
            formatNotification(info, this.msg_buf);

            with ( info.Active ) final switch ( info.active )
            {
                case received:
                case no_record:
                    this.log.trace(this.msg_buf);
                    break;

                case failure:
                case no_node:
                case node_disconnected:
                case node_error:
                case wrong_node:
                case unsupported:
                case timed_out:
                    this.log.error(this.msg_buf);
                    break;

                mixin(handleInvalidCases);
            }
        }
    }
}

/// Example of Task-blocking neo Get request usage with a notifier
unittest
{
    class GetExample : ExampleApp
    {
        override protected void example ( )
        {
            // Perform a blocking neo Get request. Note that the channel is
            // copied inside the client -- the user does not need to maintain
            // it after calling this method.
            this.dht.blocking.get("channel", 0x1234567812345678,
                &this.getNotifier);
        }

        // Notifier which is called when something of interest happens to
        // the Get request. See dhtproto.client.request.Get for
        // details of the parameters of the notifier.
        private void getNotifier ( DhtClient.Neo.Get.Notification info,
            DhtClient.Neo.Get.Args args )
        {
            formatNotification(info, this.msg_buf);

            with ( info.Active ) final switch ( info.active )
            {
                case received:
                case no_record:
                    this.log.trace(this.msg_buf);
                    break;

                case failure:
                case no_node:
                case node_disconnected:
                case node_error:
                case wrong_node:
                case unsupported:
                case timed_out:
                    this.log.error(this.msg_buf);
                    break;

                mixin(handleInvalidCases);
            }
        }
    }
}

/// Example of simple Task-blocking neo Get request usage without a notifier
unittest
{
    class GetExample : ExampleApp
    {
        override protected void example ( )
        {
            // Perform a blocking neo Get request and return a result struct
            // indicating success/failure. Notes:
            // 1. In a real application, you probably want more information than
            //    just success/failure and should use the task-blocking method
            //    with a notifier (see example above).
            // 2. The channel is copied inside the client -- the user does not
            //    need to maintain it after calling this method.
            void[] get_buf;
            auto result = this.dht.blocking.get("channel", 0x1234567812345678,
                get_buf);
            if ( result.succeeded )
            {
                if ( result.value.length )
                    this.log.trace("Get succeeded: {}", result.value);
                else
                    this.log.trace("Get succeeded: no record");
            }
            else
                this.log.error("Get failed");
        }
    }
}

/// Example of neo Mirror request usage
unittest
{
    class MirrorExample : ExampleApp
    {
        // Id of the running Mirror request
        private DhtClient.Neo.RequestId rq_id;

        override protected void example ( )
        {
            // Optional mirror settings. This example just sets the default
            // value for each field, but different behaviour can be configured
            // by setting different values. See dhtproto.client.request.Mirror.
            DhtClient.Neo.Mirror.Settings mirror_settings;
            mirror_settings.initial_refresh = true;
            mirror_settings.periodic_refresh_s = 360;

            // Assign a neo Mirror request. Note that the channel is copied
            // inside the client -- the user does not need to maintain it after
            // calling this method.
            this.rq_id = this.dht.neo.mirror("channel", &this.mirrorNotifier,
                mirror_settings);
        }

        // Notifier which is called when something of interest happens to
        // the Mirror request. See dhtproto.client.request.Mirror for
        // details of the parameters of the notifier.
        private void mirrorNotifier ( DhtClient.Neo.Mirror.Notification info,
            DhtClient.Neo.Mirror.Args args )
        {
            formatNotification(info, this.msg_buf);

            with ( info.Active ) final switch ( info.active )
            {
                case updated:
                    this.log.trace(this.msg_buf);

                    // Here we use the controller to cleanly end the request
                    // after a while
                    static ubyte count;
                    if ( ++count >= 10 )
                        this.stop();
                    break;

                case started:
                case refreshed:
                case deleted:
                case channel_removed:
                case stopped:
                case suspended:
                case resumed:
                    this.log.trace(this.msg_buf);
                    break;

                case updates_lost:
                    this.log.warn(this.msg_buf);
                    break;

                case node_disconnected:
                case node_error:
                case unsupported:
                    this.log.error(this.msg_buf);
                    break;

                mixin(handleInvalidCases);
            }
        }

        // Method which is called from the `updated` case of the notifier
        // (above). Sends a message to the DHT to cleanly stop handling this
        // request.
        private void stop ( )
        {
            // The control() method of the client allows you to get access
            // to an interface providing methods which control the state of
            // a request, while it's in progress. The Mirror request
            // controller interface is in dhtproto.client.request.Mirror.
            // Not all requests can be controlled in this way.
            this.dht.neo.control(this.rq_id,
                ( DhtClient.Neo.Mirror.IController mirror )
                {
                    // We tell the request to stop. This will cause a
                    // message to be sent to all DHT nodes, telling them to
                    // end the Mirror. More updates may be received while
                    // this is happening, but the notifier will be called as
                    // soon as all nodes have stopped. (There are also
                    // controller methods to suspend and resume the request
                    // on the node-side.)
                    mirror.stop();
                }
            );
        }
    }
}

/// Example of neo GetAll request usage
unittest
{
    class GetAllExample : ExampleApp
    {
        // Id of the running GetAll request
        private DhtClient.Neo.RequestId rq_id;

        override protected void example ( )
        {
            // Assign a neo GetAll request. Note that the channel is copied
            // inside the client -- the user does not need to maintain it after
            // calling this method.
            this.rq_id = this.dht.neo.getAll("channel", &this.getAllNotifier);
        }

        // Notifier which is called when something of interest happens to
        // the GetAll request. See dhtproto.client.request.GetAll for
        // details of the parameters of the notifier.
        private void getAllNotifier ( DhtClient.Neo.GetAll.Notification info,
            DhtClient.Neo.GetAll.Args args )
        {
            formatNotification(info, this.msg_buf);

            with ( info.Active ) final switch ( info.active )
            {
                case started:
                case received:
                case received_key:
                case finished:
                case stopped:
                case suspended:
                case resumed:
                    this.log.trace(this.msg_buf);
                    break;

                case node_disconnected:
                case node_error:
                case unsupported:
                    this.log.error(this.msg_buf);
                    break;

                mixin(handleInvalidCases);
            }
        }
    }
}

/// Example of Task-blocking neo GetAll request usage
unittest
{
    class GetAllExample : ExampleApp
    {
        override protected void example ( )
        {
            void[] buf;

            // Assign a neo GetAll request. Note that the channel is copied
            // inside the client -- the user does not need to maintain it after
            // calling this method.
            foreach ( k, v; this.dht.blocking.getAll("channel", buf) )
            {
                log.trace("GetAll received 0x{:x16}:{}", k, v);
            }
        }
    }
}

/// Example of Task-blocking neo GetChannels request usage
unittest
{
    class GetChannelsExample : ExampleApp
    {
        override protected void example ( )
        {
            mstring buf;

            // Assign a neo GetChannels request.
            foreach ( channel_name; this.dht.blocking.getChannels(buf) )
            {
                log.trace("GetChannels received {}", channel_name);
            }
        }
    }
}

/// Example of using the DHT client's stats APIs
unittest
{
    class StatsExample : ExampleApp
    {
        // Log on-demand stats.
        override protected void example ( )
        {
            // See DhtStats in dhtproto.client.mixins.NeoSupport and Stats in
            // swarm.neo.client.mixins.ClientCore
            auto stats = this.dht.neo.new DhtStats;

            // Connection stats.
            this.log.info("DHT nodes registered with client: {}",
                stats.num_registered_nodes);
            this.log.info("DHT nodes in initial connection establishment state: {}",
                stats.num_initializing_nodes);
            this.log.info("Current fraction of DHT nodes in initial connection establishment state: {}",
                stats.initializing_nodes_fraction);
            this.log.info("DHT nodes connected: {}",
                stats.num_connected_nodes);
            this.log.info("DHT nodes with hash ranges queried: {}",
                stats.num_nodes_known_hash_range);
            this.log.info("All DHT nodes connected?: {}",
                stats.all_nodes_connected);
            this.log.info("Current fraction of DHT nodes connected: {}",
                stats.connected_nodes_fraction);

            // Connection I/O stats.
            {
                size_t i;
                foreach ( conn_sender_io, conn_receiver_io; stats.connection_io )
                {
                    // See swarm.neo.protocol.socket.IOStats
                    this.log.info("Total bytes sent/received over connection {}: {}",
                        i++, conn_sender_io.socket.total, conn_receiver_io.socket.total);
                }
            }

            // Connection send queue stats.
            {
                size_t i;
                foreach ( send_queue; stats.connection_send_queue )
                {
                    // See swarm.neo.util.TreeQueue
                    this.log.info("Total time messages waited in send queue of connection {}: {}μs",
                        i++, send_queue.time_histogram.total_time_micros);
                }
            }

            // Request pool stats.
            this.log.info("Requests currently active: {}",
                stats.num_active_requests);
            this.log.info("Maximum active requests allowed: {}",
                stats.max_active_requests);
            this.log.info("Current fraction of maximum active requests: {}",
                stats.active_requests_fraction);

            // Per-request stats.
            auto rq_stats = this.dht.neo.new RequestStats;
            foreach ( name, stats; rq_stats.allRequests() )
            {
                // See swarm.neo.client.requests.Stats
                this.log.info("{} {} requests handled, mean time: {}μs",
                    stats.count, name, stats.mean_handled_time_micros);
            }
        }

        // Pass the neo client's stats to the stats logger.
        override protected void onStatsTimer ( )
        {
            // See DhtStats in dhtproto.client.mixins.NeoSupport and Stats in
            // swarm.neo.client.mixins.ClientCore
            auto stats = this.dht.neo.new DhtStats;

            // Create a struct like this to contain all the stats you want to log.
            // The field names and types must match the names and return values of
            // getter methods in DhtStats (or its base class Stats).
            struct StatsAggregate
            {
                size_t num_active_requests;
                size_t max_active_requests;
                double active_requests_fraction;
                size_t num_registered_nodes;
                size_t num_initializing_nodes;
                double initializing_nodes_fraction;
                size_t num_connected_nodes;
                bool all_nodes_connected;
                double connected_nodes_fraction;
            }

            // Fills in an instance of StatsAggregate by calling the corresponding
            // getters from `stats` and passes the struct to the logger.
            this.dht.neo.logStatsFromAggregate!(StatsAggregate)(stats,
                this.stats_ext.stats_log);

            // Logs all per-request stats.
            auto rq_stats = this.dht.neo.new RequestStats;
            rq_stats.log(this.stats_ext.stats_log);
        }
    }
}
