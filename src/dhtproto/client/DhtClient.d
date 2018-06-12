/*******************************************************************************

    Asynchronous/event-driven Dht client using non-blocking socket I/O (epoll)

    Documentation:

    For detailed documentation see dhtproto.client.README.


    Basic usage example:

    The following steps should be followed to set up and use the dht client:

        1. Create an EpollSelectDispatcher instance (see ocean.io.select).
        2. Create a DhtClient instance, pass the epoll select dispatcher and the
           maximum number of connections per node as constructor arguments.
        3. Add the dht nodes connection data by calling addNode() for each dht
           node to connect to. (Or simply call addNodes(), passing the path of
           a .nodes file describing the list of nodes to connect to.)
        4. Initiate the node handshake, and check that no error occurred.
        5. Add one or multiple requests by calling one of the client request
           methods and passing the resulting object to the client's assign()
           method.

    Example: Use at most five connections to each dht node, connect to nodes
    running at 192.168.1.234:56789 and 192.168.9.87:65432 and perform a Get
    request.

    ---

        import ocean.io.select.EpollSelectDispatcher;
        import dhtproto.client.DhtClient;

        hash_t key = 0xC001D00D;             // record key to fetch
        mstring val;                         // record value destination string


        // Error flag, set to true when a request error occurs.
        bool error;

        // Request notification callback. Sets the error flag on failure.
        void notify ( DhtClient.RequestNotification info )
        {
            if ( info.type == info.type.Finished && !info.succeeded )
            {
                error = true;
            }
        }

        // Handshake callback. Sets the error flag on handshake failure.
        void handshake ( DhtClient.RequestContext context, bool ok )
        {
            error = !ok;
        }

        // Callback delegate to receive value
        void receive_value ( DhtClient.RequestContext context, cstring value )
        {
            if ( value.length )
            {
                val.length = value.length;
                val[] = value[];
                // the above array copy can also be achieved using ocean.core.Array : copy
            }
        }


        // Initialise epoll -- Step 1
        auto epoll = new EpollSelectDispatcher;

        // Initialise dht client -- Step 2
        const NumConnections = 5;
        auto dht = new DhtClient(epoll, NumConnections);

        // Add nodes -- Step 3
        dht.addNode("192.168.1.234", 56789);
        dht.addNode("192.168.9.87",  65432);

        // Perform node handshake -- Step 4
        dht.nodeHandshake(&handshake, &notify);
        epoll.eventLoop();

        if ( error )
        {
            throw new Exception("Error during node handshake");
        }

        // Perform a Get request -- Step 5
        dht.assign(dht.get("my_channel", key, &receive_value, &notify));
        epoll.eventLoop();

        // val now contains the value corresponding to key (or "" if the key did
        // not exist in the dht)

    ---


    Useful build flags:
    ============================================================================

    -debug=SwarmClient: trace outputs noting when requests begin, end, etc

    -debug=ISelectClient: trace outputs noting epoll registrations and events
        firing

    -debug=Raw: trace outputs noting raw data sent & received via epoll

    Copyright:
        Copyright (c) 2011-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.DhtClient;



/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import swarm.util.ExtensibleClass;
import swarm.Const;
import swarm.util.Hash : HashRange;

import swarm.client.model.IClient;
import swarm.client.model.ClientSettings;

import swarm.client.ClientExceptions;
import swarm.client.ClientCommandParams;

import swarm.client.request.model.ISuspendableRequest;
import swarm.client.request.model.IStreamInfo;

import swarm.client.request.notifier.IRequestNotification;

import swarm.client.connection.RequestOverflow;

import swarm.client.helper.GroupRequest;

import swarm.client.plugins.RequestQueueDiskOverflow;
import swarm.client.plugins.RequestScheduler;
import swarm.client.plugins.ScopeRequests;

import dhtproto.client.legacy.internal.registry.model.IDhtNodeRegistryInfo;

import dhtproto.client.legacy.internal.registry.DhtNodeRegistry;

import dhtproto.client.legacy.internal.DhtClientExceptions;

import dhtproto.client.legacy.internal.request.notifier.RequestNotification;

import dhtproto.client.legacy.internal.request.params.RequestParams;

import dhtproto.client.legacy.internal.RequestSetup;

import dhtproto.client.legacy.DhtConst;

import ocean.core.Array : copy, endsWith;

import ocean.io.select.EpollSelectDispatcher;

import ocean.core.Enforce;
import ocean.core.Verify;

debug ( SwarmClient ) import ocean.io.Stdout;

import ocean.transition;


/*******************************************************************************

    Extensible DHT Client.

    Supported plugin classes can be passed as template parameters, an instance
    of each of these classes must be passed to the constructor. For each plugin
    class members may be added, depending on the particular plugin class.

    Note that the call to setPlugins(), in the class' ctors, *must* occur before
    the super ctor is called. This is because plugins may rely on the ctor being
    able to access their properly initialised instance, usually via an
    overridden method. The RequestQueueDiskOverflow plugin works like this, for
    example.

    Currently supported plugin classes:
        see dhtproto.client.legacy.internal.plugins
        and swarm.client.plugins

*******************************************************************************/

public class ExtensibleDhtClient ( Plugins ... ) : DhtClient
{
    mixin ExtensibleClass!(Plugins);


    /***************************************************************************

        Constructor with support for only the legacy protocol. Automatically
        calls addNodes() with the node definition file specified in the Config
        instance.

        Params:
            epoll = EpollSelectDispatcher instance to use
            plugin_instances = instances of Plugins
            config = Instance of the configuration class
            fiber_stack_size = size of connection fibers' stack (in bytes)

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll, Plugins plugin_instances,
        IClient.Config config,
        size_t fiber_stack_size = IClient.default_fiber_stack_size )
    {
        this.setPlugins(plugin_instances);

        super(epoll, config, fiber_stack_size);
    }


    /***************************************************************************

        Constructor with support for only the legacy protocol. This constructor
        that accepts all arguments manually (i.e. not read from a config file)
        is mostly of use in tests.

        Params:
            epoll = EpollSelectDispatcher instance to use
            plugin_instances = instances of Plugins
            conn_limit = maximum number of connections to each DHT node
            queue_size = maximum size of the per-node request queue
            fiber_stack_size = size of connection fibers' stack (in bytes)

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll, Plugins plugin_instances,
        size_t conn_limit = IClient.Config.default_connection_limit,
        size_t queue_size = IClient.Config.default_queue_size,
        size_t fiber_stack_size = IClient.default_fiber_stack_size )
    {
        this.setPlugins(plugin_instances);

        super(epoll, conn_limit, queue_size, fiber_stack_size);
    }


    /***************************************************************************

        Constructor with support for the neo and legacy protocols. Automatically
        calls addNodes() with the node definition files specified in the legacy
        and neo Config instances.

        Params:
            epoll = EpollSelectDispatcher instance to use
            plugin_instances = instances of Plugins
            config = swarm.client.model.IClient.Config instance. (The Config
                class is designed to be read from an application's config.ini
                file via ocean.util.config.ConfigFiller.)
            neo_config = swarm.neo.client.mixins.ClientCore.Config instance.
                (The Config class is designed to be read from an application's
                config.ini file via ocean.util.config.ConfigFiller.)
            conn_notifier = delegate which is called when a connection attempt
                succeeds or fails (including when a connection is
                re-established). Of type:
                void delegate ( IPAddress node_address, Exception e )
            fiber_stack_size = size (in bytes) of stack of individual connection
                fibers

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll, Plugins plugin_instances,
        IClient.Config config, Neo.Config neo_config,
        Neo.DhtConnectionNotifier conn_notifier,
        size_t fiber_stack_size = IClient.default_fiber_stack_size )
    {
        this.setPlugins(plugin_instances);

        super(epoll, config, neo_config, conn_notifier, fiber_stack_size);
    }


    /***************************************************************************

        Constructor with support for the neo and legacy protocols. This
        constructor that accepts all arguments manually (i.e. not read from
        config files) is mostly of use in tests.

        Params:
            epoll = EpollSelectDispatcher instance to use
            plugin_instances = instances of Plugins
            auth_name = client name for authorisation
            auth_key = client key (password) for authorisation. This should be a
                cryptographic random number which only the client and the
                nodes know. See `README_client_neo.rst` for suggestions. The key
                must be of the length defined in
                swarm.neo.authentication.HmacDef (128 bytes)
            conn_notifier = delegate which is called when a connection attempt
                succeeds or fails (including when a connection is
                re-established). Of type:
                void delegate ( IPAddress node_address, Exception e )
            conn_limit = maximum number of connections to each DHT node
            queue_size = maximum size of the per-node request queue
            fiber_stack_size = size of connection fibers' stack (in bytes)

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll, Plugins plugin_instances,
        cstring auth_name, ubyte[] auth_key,
        Neo.DhtConnectionNotifier conn_notifier,
        size_t conn_limit = IClient.Config.default_connection_limit,
        size_t queue_size = IClient.Config.default_queue_size,
        size_t fiber_stack_size = IClient.default_fiber_stack_size )
    {
        this.setPlugins(plugin_instances);

        super(epoll, auth_name, auth_key, conn_notifier,
                conn_limit, queue_size, fiber_stack_size);
    }
}


/*******************************************************************************

    DhtClient with a scheduler, with simplified constructor.

    (This instantiation of the ExtensibleDhtClient template is provided for
    convenience, as it is a commonly used case.)

*******************************************************************************/

public class SchedulingDhtClient : ExtensibleDhtClient!(RequestScheduler)
{
    static class Config : IClient.Config
    {
        /***********************************************************************

            Limit on the number of events which can be managed by the scheduler
            at one time (0 = no limit)

        ***********************************************************************/

        uint scheduler_limit = 0;
    }


    /***************************************************************************

        Constructor with support for only the legacy protocol. Automatically
        calls addNodes() with the node definition file specified in the Config
        instance.

        Params:
            epoll = EpollSelectorDispatcher instance to use
            config = Config instance
            fiber_stack_size = size of connection fibers' stack (in bytes)

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll, SchedulingDhtClient.Config config,
        size_t fiber_stack_size = IClient.default_fiber_stack_size )
    {
        super(epoll, new RequestScheduler(epoll, config.scheduler_limit),
            config, fiber_stack_size);
    }


    /***************************************************************************

        Constructor with support for only the legacy protocol. This constructor
        that accepts all arguments manually (i.e. not read from a config file)
        is mostly of use in tests.

        Params:
            epoll = EpollSelectorDispatcher instance to use
            conn_limit = maximum number of connections to each DHT node
            queue_size = maximum size of the per-node request queue
            fiber_stack_size = size of connection fibers' stack (in bytes)
            max_events = limit on the number of events which can be managed
                by the scheduler at one time. (0 = no limit)

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll,
        size_t conn_limit = IClient.Config.default_connection_limit,
        size_t queue_size = IClient.Config.default_queue_size,
        size_t fiber_stack_size = IClient.default_fiber_stack_size,
        uint max_events = 0 )
    {
        super(epoll, new RequestScheduler(epoll, max_events), conn_limit,
            queue_size, fiber_stack_size);
    }

    /***************************************************************************

        Constructor with support for the neo and legacy protocols. Automatically
        calls addNodes() with the node definition files specified in the legacy
        and neo Config instances.

        Params:
            epoll = EpollSelectDispatcher instance to use
            config = SchedulingDhtClient.Config instance. (The Config class is
                designed to be read from an application's config.ini file via
                ocean.util.config.ConfigFiller.)
            neo_config = swarm.neo.client.mixins.ClientCore.Config instance.
                (The Config class is designed to be read from an application's
                config.ini file via ocean.util.config.ConfigFiller.)
            conn_notifier = delegate which is called when a connection attempt
                succeeds or fails (including when a connection is
                re-established). Of type:
                void delegate ( IPAddress node_address, Exception e )
            fiber_stack_size = size (in bytes) of stack of individual connection
                fibers

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll,
        SchedulingDhtClient.Config config,
        Neo.Config neo_config, Neo.DhtConnectionNotifier conn_notifier,
        size_t fiber_stack_size = IClient.default_fiber_stack_size )
    {
        super(epoll, new RequestScheduler(epoll, config.scheduler_limit),
            config, neo_config, conn_notifier, fiber_stack_size);
    }


    /***************************************************************************

        Constructor with support for the neo and legacy protocols. This
        constructor that accepts all arguments manually (i.e. not read from
        config files) is mostly of use in tests.

        Params:
            epoll = EpollSelectDispatcher instance to use
            auth_name = client name for authorisation
            auth_key = client key (password) for authorisation. This should be a
                cryptographic random number which only the client and the
                nodes know. See `README_client_neo.rst` for suggestions. The key
                must be of the length defined in
                swarm.neo.authentication.HmacDef (128 bytes)
            conn_notifier = delegate which is called when a connection attempt
                succeeds or fails (including when a connection is
                re-established). Of type:
                void delegate ( IPAddress node_address, Exception e )
            conn_limit = maximum number of connections to each DHT node
            queue_size = maximum size of the per-node request queue
            fiber_stack_size = size of connection fibers' stack (in bytes)
            max_events = limit on the number of events which can be managed
                by the scheduler at one time. (0 = no limit)

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll,
        cstring auth_name, ubyte[] auth_key,
        Neo.DhtConnectionNotifier conn_notifier,
        size_t conn_limit = IClient.Config.default_connection_limit,
        size_t queue_size = IClient.Config.default_queue_size,
        size_t fiber_stack_size = IClient.default_fiber_stack_size,
        uint max_events = 0 )
    {
        super(epoll, new RequestScheduler(epoll, max_events),
            auth_name, auth_key, conn_notifier,
            conn_limit,
            queue_size, fiber_stack_size);
    }
}


/*******************************************************************************

    DHT Client

*******************************************************************************/

public class DhtClient : IClient
{
    /***************************************************************************

        Local alias definitions

    ***************************************************************************/

    public alias .IRequestNotification RequestNotification;
    public alias .ISuspendableRequest ISuspendableRequest;
    public alias .IStreamInfo IStreamInfo;
    public alias .RequestParams RequestParams;


    /***************************************************************************

        Plugin alias definitions

    ***************************************************************************/

    public alias .RequestScheduler RequestScheduler;

    public alias .RequestQueueDiskOverflow RequestQueueDiskOverflow;

    public alias .ScopeRequestsPlugin ScopeRequestsPlugin;


    /***************************************************************************

        Node handshake class, used by the DhtClient.nodeHandshake() method to
        synchronize the initial contacting of the dht nodes and checking of the
        API version and fetching of the nodes' hash ranges.

    ***************************************************************************/

    private class NodeHandshake
    {
        /***********************************************************************

            Delegate to be called when the handshake has finished, indicating
            sucecss or failure.

        ***********************************************************************/

        private RequestParams.GetBoolDg output;


        /***********************************************************************

            Request notification delegate.

        ***********************************************************************/

        private alias RequestNotification.Callback NotifierDg;

        private NotifierDg user_notifier;


        /***********************************************************************

            Counters to track how many out of all registered nodes have returned
            for each request.

        ***********************************************************************/

        private uint version_done_count;

        private uint ranges_done_count;


        /***********************************************************************

            opCall -- initialises a node handshake for the specified dht client.

            Params:
                output = delegate called when handshake is complete
                user_notifier = request notification delegate

        ***********************************************************************/

        public void opCall ( scope RequestParams.GetBoolDg output,
            NotifierDg user_notifier )
        {
            this.reset(output, user_notifier);

            with ( this.outer )
            {
                assign(getVersion(&this.getVersionIO, &this.handshakeNotifier));

                assign(getResponsibleRange(&this.getResponsibleRangeIO,
                    &this.handshakeNotifier));
            }
        }


        /***********************************************************************

            Resets all members ready to start a new handshake.

            Params:
                output = delegate called when handshake is complete
                user_notifier = request notification delegate

        ***********************************************************************/

        private void reset ( scope RequestParams.GetBoolDg output,
            NotifierDg user_notifier )
        {
            this.output = output;
            this.user_notifier = user_notifier;

            this.version_done_count = 0;
            this.ranges_done_count = 0;
        }


        /***********************************************************************

            Notification callback used for all internally assigned dht requests.

            Params:
                info = request notification info

            TODO: could the bool delegate be replaced with a series of exceptions
            which are sent to the notifier to denote different handshake errors?

        ***********************************************************************/

        private void handshakeNotifier ( DhtClient.RequestNotification info )
        {
            if ( this.user_notifier !is null )
            {
                this.user_notifier(info);
            }

            if ( info.type == info.type.Finished )
            {
                with ( DhtConst.Command.E ) switch ( info.command )
                {
                    case GetVersion:            this.version_done_count++; break;
                    case GetResponsibleRange:   this.ranges_done_count++; break;

                    default:
                        assert(false);
                }

                auto dht_registry = cast(IDhtNodeRegistryInfo)this.outer.nodes;
                verify(dht_registry !is null);

                if ( this.version_done_count == dht_registry.length &&
                     this.ranges_done_count == dht_registry.length )
                {
                    this.output(RequestContext(0), dht_registry.all_nodes_ok);
                }
            }
        }


        /***********************************************************************

            GetVersion request callback.

            Params:
                context = request context (not used)
                api_version = api version received from node

        ***********************************************************************/

        private void getVersionIO ( RequestContext context, in cstring address,
            ushort port, in cstring api_version )
        {
            debug ( SwarmClient ) Stderr.formatln("Received version {}:{} = '{}'",
                address, port, api_version);

            (cast(DhtNodeRegistry)this.outer.registry).setNodeAPIVersion(
                address.dup, port, api_version);
        }


        /***********************************************************************

            GetResponsibleRange request callback.

            Params:
                context = request context (not used)
                address = address received from node
                port = port received from node
                range = hash range received from node

            Throws:
                NodeOverlapException if another node in the registry is already
                known to be responsible for part of the specified hash range

        ***********************************************************************/

        private void getResponsibleRangeIO ( RequestContext context, in cstring address,
            ushort port, HashRange range )
        {
            debug ( SwarmClient ) Stderr.formatln("Received hash range = {}:{} -- "
                ~ "0x{:x}..0x{:x}", address, port, range.min, range.max);

            (cast(DhtNodeRegistry)this.outer.registry).setNodeResponsibleRange(
                address.dup, port, range.min, range.max);
        }
    }


    /***************************************************************************

        Node handshake instance.

        TODO: using a single struct instance means that only one node handshake
        can be active at a time. This is ok, but there's no way of enforcing it.
        This could probably be reworked if we implement the request-grouping
        feature for multi-node commands, or if the node handshake is moved to an
        internal-only process.

    ***************************************************************************/

    private NodeHandshake node_handshake;


    /***************************************************************************

        Exceptions thrown in error cases.

    ***************************************************************************/

    private BadChannelNameException bad_channel_exception;

    private NullFilterException null_filter_exception;


    /***************************************************************************

        Neo protocol support.

    ***************************************************************************/

    import dhtproto.client.mixins.NeoSupport;

    mixin NeoSupport!();


    /***************************************************************************

        Constructor with support for only the legacy protocol. Automatically
        calls addNodes() with the node definition file specified in the Config
        instance.

        Params:
            epoll = EpollSelectorDispatcher instance to use
            config = Config instance (see swarm.client.model.IClient. The
                Config class is designed to be read from an application's
                config.ini file via ocean.util.config.ConfigFiller)
            fiber_stack_size = size (in bytes) of stack of individual connection
                fibers

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll, IClient.Config config,
        size_t fiber_stack_size = IClient.default_fiber_stack_size )
    {
        with ( config )
        {
            this(epoll, connection_limit(), queue_size(), fiber_stack_size);

            this.addNodes(nodes_file);
        }
    }


    /***************************************************************************

        Constructor with support for only the legacy protocol. This constructor
        that accepts all arguments manually (i.e. not read from a config file)
        is mostly of use in tests.

        Params:
            epoll = EpollSelectorDispatcher instance to use
            conn_limit = maximum number of connections to each DHT node
            queue_size = maximum size of the per-node request queue
            fiber_stack_size = size (in bytes) of stack of individual connection
                fibers

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll,
        size_t conn_limit = IClient.Config.default_connection_limit,
        size_t queue_size = IClient.Config.default_queue_size,
        size_t fiber_stack_size = IClient.default_fiber_stack_size )
    {
        ClientSettings settings;
        settings.conn_limit = conn_limit;
        settings.queue_size = queue_size;
        settings.fiber_stack_size = fiber_stack_size;

        auto node_registry = this.newDhtNodeRegistry(epoll, settings,
            this.requestOverflow, this.errorReporter);
        super(epoll, node_registry);

        this.bad_channel_exception = new BadChannelNameException;
        this.null_filter_exception = new NullFilterException;

        this.node_handshake = new NodeHandshake;
    }


    /***************************************************************************

        Constructor with support for the neo and legacy protocols. Automatically
        calls addNodes() with the node definition files specified in the legacy
        and neo Config instances.

        Params:
            epoll = EpollSelectDispatcher instance to use
            config = swarm.client.model.IClient.Config instance. (The Config
                class is designed to be read from an application's config.ini
                file via ocean.util.config.ConfigFiller.)
            neo_config = swarm.neo.client.mixins.ClientCore.Config instance.
                (The Config class is designed to be read from an application's
                config.ini file via ocean.util.config.ConfigFiller.)
            conn_notifier = delegate which is called when a connection attempt
                succeeds or fails (including when a connection is
                re-established). Of type:
                void delegate ( IPAddress node_address, Exception e )
            fiber_stack_size = size (in bytes) of stack of individual connection
                fibers

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll, IClient.Config config,
        Neo.Config neo_config, Neo.DhtConnectionNotifier conn_notifier,
        size_t fiber_stack_size = IClient.default_fiber_stack_size )
    {
        with ( config )
        {
            this(epoll, connection_limit(), queue_size(), fiber_stack_size);

            this.addNodes(nodes_file);
        }

        this.neoInit(neo_config, conn_notifier);
    }


    /***************************************************************************

        Constructor with support for the neo and legacy protocols. This
        constructor that accepts all arguments manually (i.e. not read from
        config files) is mostly of use in tests.

        Params:
            epoll = EpollSelectDispatcher instance to use
            auth_name = client name for authorisation
            auth_key = client key (password) for authorisation. This should be a
                cryptographic random number which only the client and the
                nodes know. See `README_client_neo.rst` for suggestions. The key
                must be of the length defined in
                swarm.neo.authentication.HmacDef (128 bytes)
            conn_notifier = delegate which is called when a connection attempt
                succeeds or fails (including when a connection is
                re-established). Of type:
                void delegate ( IPAddress node_address, Exception e )
            conn_limit = maximum number of connections to each DHT node
            queue_size = maximum size of the per-node request queue
            fiber_stack_size = size of connection fibers' stack (in bytes)

    ***************************************************************************/

    public this ( EpollSelectDispatcher epoll, cstring auth_name, ubyte[] auth_key,
        Neo.DhtConnectionNotifier conn_notifier,
        size_t conn_limit = IClient.Config.default_connection_limit,
        size_t queue_size = IClient.Config.default_queue_size,
        size_t fiber_stack_size = IClient.default_fiber_stack_size )
    {
        this(epoll, conn_limit, queue_size, fiber_stack_size);

        this.neoInit(auth_name, auth_key, conn_notifier);
    }


    /***************************************************************************

        Constructs the client's dht node registry. Derived classes may override
        in order to construct specialised types of registry.

        Params:
            epoll = epoll instance
            settings = client settings instance
            request_overflow = overflow handler for requests which don't fit in
                the request queue
            error_reporter = error reporter instance to notify on error or
                timeout

        Returns:
            new DhtNodeRegistry instance

    ***************************************************************************/

    protected DhtNodeRegistry newDhtNodeRegistry ( EpollSelectDispatcher epoll,
        ClientSettings settings, IRequestOverflow request_overflow,
        INodeConnectionPoolErrorReporter error_reporter )
    {
        return new DhtNodeRegistry(epoll, settings, request_overflow,
            error_reporter);
    }


    /***************************************************************************

        Initiates the connection with all registered dht nodes. This involves
        the following steps:

            1. The API version number is requested from all registered nodes.
               These version numbers are cross-checked against each other and
               against the client's API version.
            2. Hash responsibility range is requested from all registered nodes.
               The hash ranges are checked for consistency (covering the
               complete hash range without gaps or overlaps).

        The specified user notification delegate is called for each node for
        each request performed by the node handshake (i.e. GetVersion,
        GetReponsibleRange).

        The specified output delegate is called once when the handshakes with
        all nodes have completed, indicating whether the handshakes were
        successful or not.

        Note that it is possible to continue using the client even if the
        handshake fails. Certain requests may fail, in this case, (for example
        a request which operates on a single key for which no responsible node
        is known). It is recommended that, if you continue using the client
        after a failed handshake, that you retry the handshake periodically, so
        that eventually you get the complete picture.

        TODO: try restructuring so that the node handshake is done internally
        upon assigning the first normal request (so the node handshake needn't
        be explicitly called by the user). In this case, the notifier in the
        node handshake struct would actually assign the requested method when
        the handshake succeeds, and would call the notifier with an error code
        if it fails (need to make sure all the appropriate error codes exist...
        version mismatch doesn't atm).

        Params:
            output = output delegate which receives a bool telling whether the
                handshake succeeded or not
            user_notifier = notification delegate

    ***************************************************************************/

    public void nodeHandshake ( scope RequestParams.GetBoolDg output,
        scope RequestNotification.Callback user_notifier )
    {
        this.node_handshake(output, user_notifier);
    }


    /***************************************************************************

        Assigns a new request to the client. The request is validated, and the
        notification callback may be invoked immediately if any errors are
        detected. Otherwise the request is sent to the node registry, where it
        will be either executed immediately (if a free connection is available)
        or queued for later execution.

        Template params:
            T = request type (should be one of the structs defined in this
                module)

        Params:
            request = request to assign

    ***************************************************************************/

    public void assign ( T ) ( T request )
    {
        static if ( is(T : IGroupRequest) )
        {
            request.setClient(this);
        }

        this.scopeRequestParams(
            ( IRequestParams params )
            {
                request.setup(params);

                this.assignParams(params);
            });
    }


    /***************************************************************************

        Creates a Put request, which will send a single value with the specified
        key to the dht. The database record value is read from the specified
        input delegate, which should be of the form:

            Const!(char)[] delegate ( RequestContext context )

        It is illegal to put empty values to the node.

        Params:
            channel = database channel
            key = database record key
            input = input delegate which provides record value to send
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct Put
    {
        mixin RequestBase;
        mixin IODelegate;       // io(T) method
        mixin Channel;          // channel(cstring) method
        mixin Key;              // key ( K ) (K) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public Put put ( Key ) ( cstring channel, Key key, scope RequestParams.PutValueDg input,
                             scope RequestNotification.Callback notifier )
    {
        return *Put(DhtConst.Command.E.Put, notifier).channel(channel).key(key)
            .io(input).contextFromKey();
    }


    /***************************************************************************

        Creates a Get request, which will receive a single value with the
        specified key from the dht. The database record value is sent to the
        specified output delegate, which should be of the form:

            void delegate ( RequestContext context, in char[] value )

        If the key does not exist in the dht, then an empty string is received.

        Params:
            channel = database channel
            key = database record key
            output = output delegate to send record value to
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct Get
    {
        mixin RequestBase;
        mixin IODelegate;       // io(T) method
        mixin Channel;          // channel(cstring) method
        mixin Key;              // key ( K ) (K) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public Get get ( Key ) ( cstring channel, Key key, scope RequestParams.GetValueDg output,
            scope RequestNotification.Callback notifier )
    {
        return *Get(DhtConst.Command.E.Get, notifier).channel(channel).key(key)
            .io(output).contextFromKey();
    }


    /***************************************************************************

        Creates an Exists request, which will receive a bool from the dht
        indicating whether a reocrd with the specified key exists. The bool is
        sent to the specified output delegate, which should be of the form:

            void delegate ( RequestContext context, bool exists )

        Params:
            channel = database channel
            key = database record key
            output = output delegate to send bool to
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct Exists
    {
        mixin RequestBase;
        mixin IODelegate;       // io(T) method
        mixin Channel;          // channel(cstring) method
        mixin Key;              // key ( K ) (K) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public Exists exists ( Key ) ( cstring channel, Key key, scope RequestParams.GetBoolDg output,
            scope RequestNotification.Callback notifier )
    {
        return *Exists(DhtConst.Command.E.Exists, notifier).channel(channel)
            .key(key).io(output).contextFromKey();
    }


    /***************************************************************************

        Creates a Remove request, which will request that the dht remove the
        value with the specified key, if it exists.

        Params:
            channel = database channel
            key = database record key
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct Remove
    {
        mixin RequestBase;
        mixin Channel;          // channel(cstring) method
        mixin Key;              // key ( K ) (K) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public Remove remove ( Key ) ( cstring channel, Key key, scope RequestNotification.Callback notifier )
    {
        return *Remove(DhtConst.Command.E.Remove, notifier).channel(channel)
            .key(key).contextFromKey();
    }


    /***************************************************************************

        Creates a GetAll request, which will receive all values in the specified
        channel from the dht. The database record keys & values are sent to the
        specified output delegate, which should be of the form:

            void delegate ( RequestContext context, in char[] key, in char[] value )

        Note that if there are no records in the specified channel, the output
        delegate will not be called.

        This is a multi-node request which is executed in parallel over all
        nodes in the dht.

        Params:
            channel = database channel
            output = output delegate to send record keys & values to
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct GetAll
    {
        mixin RequestBase;
        mixin IODelegate;       // io(T) method
        mixin Channel;          // channel(cstring) method
        mixin Filter;           // filter(char[]) method
        mixin Suspendable;      // suspendable(RequestParams.RegisterSuspendableDg) method
        mixin StreamInfo;       // stream_info(RequestParams.RegisterStreamInfoDg) method
        mixin Node;             // node(NodeItem) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public GetAll getAll ( cstring channel, scope RequestParams.GetPairDg output,
            scope RequestNotification.Callback notifier )
    {
        return *GetAll(DhtConst.Command.E.GetAll, notifier).channel(channel)
            .io(output);
    }


    /***************************************************************************

        Creates a GetAllKeys request, which will receive the keys of all values
        in the specified channel from the dht. The database record keys are sent
        to the specified output delegate, which should be of the form:

            void delegate ( RequestContext context, in char[] key )

        Note that if there are no records in the specified channel, the output
        delegate will not be called.

        This is a multi-node request which is executed in parallel over all
        nodes in the dht.

        Params:
            channel = database channel
            output = output delegate to send record keys to
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct GetAllKeys
    {
        mixin RequestBase;
        mixin IODelegate;       // io(T) method
        mixin Channel;          // channel(cstring) method
        mixin Suspendable;      // suspendable(RequestParams.RegisterSuspendableDg) method
        mixin StreamInfo;       // stream_info(RequestParams.RegisterStreamInfoDg) method
        mixin Node;             // node(NodeItem) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public GetAllKeys getAllKeys ( cstring channel, scope RequestParams.GetValueDg output,
            scope RequestNotification.Callback notifier )
    {
        return *GetAllKeys(DhtConst.Command.E.GetAllKeys, notifier)
            .channel(channel).io(output);
    }


    /***************************************************************************

        Creates a Listen request, which will receive a stream of values in the
        specified channel from the dht. The record keys & values are received as
        they are added to the dht with one of the Put* commands. The database
        record keys & values are sent to the specified output delegate, which
        should be of the form:

            void delegate ( RequestContext context, in char[] key, in char[] value )

        This is a multi-node request which is executed in parallel over all
        nodes in the dht.

        Params:
            channel = database channel
            output = output delegate to send record keys & values to
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct Listen
    {
        mixin RequestBase;
        mixin IODelegate;       // io(T) method
        mixin Channel;          // channel(cstring) method
        mixin Suspendable;      // suspendable(RequestParams.RegisterSuspendableDg) method
        mixin StreamInfo;       // stream_info(RequestParams.RegisterStreamInfoDg) method
        mixin Node;             // node(NodeItem) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public Listen listen ( cstring channel, scope RequestParams.GetPairDg output,
            scope RequestNotification.Callback notifier )
    {
        return *Listen(DhtConst.Command.E.Listen, notifier).channel(channel)
            .io(output);
    }


    /***************************************************************************

        Creates a GetChannels request, which will receive a list of all channels
        which exist in the dht. The channel names are sent to the specified
        output delegate, which should be of the form:

            void delegate ( RequestContext context, char[] address, ushort port,
                    cstring channel )

        This is a multi-node request which is executed in parallel over all
        nodes in the dht. This means that the name of each channel will most
        likely be received once from each node.

        Note that if there are no channels in the dht, the output delegate will
        not be called.

        Params:
            output = output delegate to send channel names to
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct GetChannels
    {
        mixin RequestBase;
        mixin IODelegate;       // io(T) method
        mixin Node;             // node(NodeItem) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public GetChannels getChannels ( scope RequestParams.GetNodeValueDg output,
            scope RequestNotification.Callback notifier )
    {
        return *GetChannels(DhtConst.Command.E.GetChannels, notifier).io(output);
    }


    /***************************************************************************

        Creates a GetSize request, which will receive the number of records and
        bytes which exist in each node in the dht (a sum of the contents of all
        channels stored in the node). The database sizes are sent to the
        specified output delegate, which should be of the form:

            void delegate ( RequestContext context, char[] address, ushort port, ulong records, ulong bytes )

        This is a multi-node request which is executed in parallel over all
        nodes in the dht. The output delegate is called once per node.

        Note that if there are no channels in the dht, the output delegate will
        not be called.

        Params:
            output = output delegate to send size information to
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct GetSize
    {
        mixin RequestBase;
        mixin IODelegate;       // io(T) method
        mixin Node;             // node(NodeItem) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public GetSize getSize ( scope RequestParams.GetSizeInfoDg output, scope RequestNotification.Callback notifier )
    {
        return *GetSize(DhtConst.Command.E.GetSize, notifier).io(output);
    }


    /***************************************************************************

        Creates a GetChannelSize request, which will receive the number of
        records and bytes which exist in the specified channel in each node of
        the dht. The channel sizes are sent to the specified output delegate,
        which should be of the form:

            void delegate ( RequestContext context, char[] address, ushort port,
                    cstring channel, ulong records, ulong bytes )

        This is a multi-node request which is executed in parallel over all
        nodes in the dht. The output delegate is called once per node.

        Note that if there are no channels in the dht, the output delegate will
        not be called.

        Params:
            channel = database channel
            output = output delegate to send size information to
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct GetChannelSize
    {
        mixin RequestBase;
        mixin Channel;          // channel(cstring) method
        mixin IODelegate;       // io(T) method
        mixin Node;             // node(NodeItem) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public GetChannelSize getChannelSize ( cstring channel, scope RequestParams.GetChannelSizeInfoDg output, scope RequestNotification.Callback notifier )
    {
        return *GetChannelSize(DhtConst.Command.E.GetChannelSize, notifier)
            .channel(channel).io(output);
    }


    /***************************************************************************

        Creates a RemoveChannel request, which will delete all records from the
        specified channel in all nodes of the dht.

        This is a multi-node request which is executed in parallel over all
        nodes in the dht.

        Params:
            channel = database channel
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct RemoveChannel
    {
        mixin RequestBase;
        mixin Channel;          // channel(cstring) method
        mixin Node;             // node(NodeItem) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public RemoveChannel removeChannel ( cstring channel, scope RequestNotification.Callback notifier )
    {
        return *RemoveChannel(DhtConst.Command.E.RemoveChannel, notifier)
            .channel(channel);
    }


    /***************************************************************************

        Creates a GetNumConnections request, which will receive the count of
        open connections being handled by each node of the dht. The number of
        connections is sent to the specified output delegate, which should be of
        the form:

            void delegate ( RequestContext context, char[] address, ushort port, size_t connections )

        This is a multi-node request which is executed in parallel over all
        nodes in the dht. The output delegate is called once per node.

        Note that if there are no channels in the dht, the output delegate will
        not be called.

        Params:
            output = output delegate to send connection counts to
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct GetNumConnections
    {
        mixin RequestBase;
        mixin IODelegate;       // io(T) method
        mixin Node;             // node(NodeItem) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public GetNumConnections getNumConnections ( scope RequestParams.GetNumConnectionsDg output,
            scope RequestNotification.Callback notifier )
    {
        return *GetNumConnections(DhtConst.Command.E.GetNumConnections, notifier)
            .io(output);
    }


    /***************************************************************************

        Creates a GetVersion request, which will receive the api version used by
        each node of the dht. The api version is sent to the specified output
        delegate, which should be of the form:

            void delegate ( RequestContext context, char[] address, ushort port,
                char[] api_version )

        This is a multi-node request which is executed in parallel over all
        nodes in the dht. The output delegate is called once per node.

        Note that if there are no channels in the dht, the output delegate will
        not be called.

        This request is usually only used internally by the node handshake.

        Params:
            output = output delegate to send api versions to
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct GetVersion
    {
        mixin RequestBase;
        mixin IODelegate;       // io(T) method
        mixin Node;             // node(NodeItem) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public GetVersion getVersion ( scope RequestParams.GetNodeValueDg output,
            scope RequestNotification.Callback notifier )
    {
        return *GetVersion(DhtConst.Command.E.GetVersion, notifier).io(output);
    }


    /***************************************************************************

        Creates a GetResponsibleRange request, which will receive the hash range
        used by each node of the dht. The hash range is sent to the specified
        output delegate, which should be of the form:

            void delegate ( RequestContext context, char[] address, ushort port, hash_t min, hash_t max )

        This is a multi-node request which is executed in parallel over all
        nodes in the dht. The output delegate is called once per node.

        Note that if there are no channels in the dht, the output delegate will
        not be called.

        This request is usually only used internally by the node handshake.

        Params:
            output = output delegate to send api versions to
            notifier = notification callback

        Returns:
            instance allowing optional settings to be set and then to be passed
            to assign()

    ***************************************************************************/

    public struct GetResponsibleRange
    {
        mixin RequestBase;
        mixin IODelegate;       // io(T) method
        mixin Node;             // node(NodeItem) method

        mixin RequestParamsSetup; // private setup() method, used by assign()
    }

    public GetResponsibleRange getResponsibleRange ( scope RequestParams.GetResponsibleRangeDg output,
            scope RequestNotification.Callback notifier )
    {
        return *GetResponsibleRange(DhtConst.Command.E.GetResponsibleRange,
            notifier).io(output);
    }


    /***************************************************************************

        Creates a new request params instance (derived from IRequestParams), and
        passes it to the provided delegate.

        This method is used by the request scheduler plugin, which needs to be
        able to construct and use a request params instance without knowing
        which derived type is used by the client.

        Params:
            dg = delegate to receive and use created scope IRequestParams
                instance

    ***************************************************************************/

    override protected void scopeRequestParams (
        scope void delegate ( IRequestParams params ) dg )
    {
        scope params = new RequestParams;
        dg(params);
    }


    /***************************************************************************

        Checks whether the given channel name is valid. Channel names can only
        contain alphanumeric characters, underscores or dashes.

        If the channel name is not valid then the user specified error callback
        is invoked with the BadChannelName status code.

        Params:
            params = request params to check

        Throws:
            * if the channel name is invalid
            * if a filtering request is being assigned but the filter string is
              empty

            (exceptions will be caught in super.assignParams)

    ***************************************************************************/

    override protected void validateRequestParams_ ( IRequestParams params )
    {
        auto dht_params = cast(RequestParams)params;

        // Validate channel name, for commands which use it
        with ( DhtConst.Command.E ) switch ( params.command )
        {
            case Put:
            case Get:
            case Exists:
            case Remove:
            case GetAll:
            case GetAllKeys:
            case GetChannelSize:
            case RemoveChannel:
            case Listen:
            case GetAllFilter:
                enforce(this.bad_channel_exception,
                    .validateChannelName(dht_params.channel));
                break;
            default:
        }

        // Validate filter string, for commands which use it
        with ( DhtConst.Command.E ) switch ( params.command )
        {
            case GetAllFilter:
                enforce(this.null_filter_exception, dht_params.filter.length);
                break;
            default:
        }
    }
}

version ( UnitTest )
{
    import ocean.io.select.EpollSelectDispatcher;
    import swarm.client.request.params.IRequestParams;
}

/*******************************************************************************

    Test instantiating clients with various plugins.

*******************************************************************************/

unittest
{
    auto epoll = new EpollSelectDispatcher;

    {
        auto dht = new ExtensibleDhtClient!(DhtClient.RequestScheduler)
            (epoll, new RequestScheduler(epoll));
    }

    {
        class DummyStore : RequestQueueDiskOverflow.IRequestStore
        {
            ubyte[] store ( IRequestParams params ) { return null; }
            void restore ( void[] stored ) { }
        }

        auto dht = new ExtensibleDhtClient!(DhtClient.RequestQueueDiskOverflow)
            (epoll, new RequestQueueDiskOverflow(new DummyStore, "dummy"));
    }

    {
        auto dht = new ExtensibleDhtClient!(DhtClient.ScopeRequestsPlugin)
            (epoll, new ScopeRequestsPlugin);
    }
}
