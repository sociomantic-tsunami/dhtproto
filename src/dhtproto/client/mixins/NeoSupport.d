/*******************************************************************************

    Neo protocol support for DhtClient.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.mixins.NeoSupport;

/*******************************************************************************

    Template wrapping access to all "neo" features. Mix this class into a
    DhtClient-derived class and construct the `neo` and 'blocking' objects in
    your constructor.

*******************************************************************************/

template NeoSupport ( )
{
    import dhtproto.client.internal.SharedResources;
    import dhtproto.client.internal.NodeHashRanges;
    import swarm.neo.AddrPort;
    import swarm.neo.client.NotifierTypes;

    /***************************************************************************

        Class wrapping access to all "neo" features. (When the old protocol is
        removed, the contents of this class will be moved into the top level of
        the client class.)

        Usage example:
            see the documented unittest, after the class definition

    ***************************************************************************/

    public class Neo
    {
        import swarm.neo.client.mixins.ClientCore;
        import swarm.neo.client.mixins.Controllers;
        import swarm.neo.client.request_options.RequestOptions;
        import ocean.core.SmartUnion;

        /***********************************************************************

            Union of connection notification types.

        ***********************************************************************/

        private union DhtConnNotificationUnion
        {
            NodeInfo connected;

            NodeInfo hash_range_queried;

            NodeExceptionInfo connection_error;
        }

        /***********************************************************************

            Smart-union of connection notification types.

        ***********************************************************************/

        private alias SmartUnion!(DhtConnNotificationUnion) DhtConnNotification;

        /***********************************************************************

            Alias for a delegate which receives a DhtConnNotification.

        ***********************************************************************/

        public alias void delegate ( DhtConnNotification ) DhtConnectionNotifier;

        /***********************************************************************

            Public imports of the request API modules, for the convenience of
            user code.

        ***********************************************************************/

        public import Put = dhtproto.client.request.Put;
        public import Get = dhtproto.client.request.Get;
        public import Mirror = dhtproto.client.request.Mirror;
        public import GetAll = dhtproto.client.request.GetAll;
        public import GetChannels = dhtproto.client.request.GetChannels;

        /***********************************************************************

            Private imports of the request implementation modules.

        ***********************************************************************/

        private struct Internals
        {
            import dhtproto.client.request.internal.GetHashRange;
            import dhtproto.client.request.internal.Put;
            import dhtproto.client.request.internal.Get;
            import dhtproto.client.request.internal.Mirror;
            import dhtproto.client.request.internal.GetAll;
            import dhtproto.client.request.internal.GetChannels;
        }

        /***********************************************************************

            Mixin core client internals (see
            swarm.neo.client.mixins.ClientCore).

        ***********************************************************************/

        mixin ClientCore!();

        /***********************************************************************

            Mixin `Controller` and `Suspendable` helper class templates (see
            swarm.neo.client.mixins.Controllers).

        ***********************************************************************/

        mixin Controllers!();

        /***********************************************************************

            Test instantiating the `Controller` and `Suspendable` class
            templates.

        ***********************************************************************/

        unittest
        {
            alias Controller!(Mirror.IController) MirrorController;
            alias Suspendable!(Mirror.IController) MirrorSuspendable;

            alias Controller!(GetAll.IController) GetAllController;
            alias Suspendable!(GetAll.IController) GetAllSuspendable;
        }

        /***********************************************************************

            DMQ request stats class. New an instance of this class to access
            per-request stats.

        ***********************************************************************/

        public alias RequestStatsTemplate!("Get", "Put", "Mirror", "GetAll",
            "GetChannels") RequestStats;

        /***********************************************************************

            DHT stats class. Extends the Stats class defined in ClientCore
            with additional, DHT-specific stats. New an instance of this class
            to access client-global stats.

        ***********************************************************************/

        public class DhtStats : Stats
        {
            /*******************************************************************

                Returns:
                    the number of nodes for which the hash-range is known

            *******************************************************************/

            public size_t num_nodes_known_hash_range ( )
            {
                return this.outer.outer.shared_resources.node_hash_ranges.length;
            }
        }

        /***********************************************************************

            Assigns a Put request, writing a record to the specified channel.
            See $(LINK2 dhtproto/client/request/Put.html, dhtproto.client.request.Put)
            for detailed documentation.

            Params:
                channel = name of the channel to write to
                key = hash of the record to write
                value = record value to write (will be copied internally)
                notifier = notifier delegate

            Returns:
                id of newly assigned request

            Throws:
                NoMoreRequests if the pool of active requests is full

            TODO: allow optional settings to be specified via varargs

        ***********************************************************************/

        public RequestId put ( cstring channel, hash_t key, Const!(void)[] value,
            Put.Notifier notifier )
        {
            auto params = Const!(Internals.Put.UserSpecifiedParams)(
                Const!(Put.Args)(channel, key, value),
                Const!(Internals.Put.UserSpecifiedParams.SerializedNotifier)(
                    *(cast(Const!(ubyte[notifier.sizeof])*)&notifier)
                )
            );

            auto id = this.assign!(Internals.Put)(params);
            return id;
        }

        /***********************************************************************

            Assigns a Get request, reading a record from the specified channel.
            See $(LINK2 dhtproto/client/request/Get.html, dhtproto.client.request.Get)
            for detailed documentation.

            Params:
                Options = tuple of types of additional arguments
                channel = name of the channel to read from
                key = hash of the record to read
                notifier = notifier delegate
                options = additional arguments. The following are supported:
                    dhtproto.client.request.Get.Timeout: sets the request to
                        time out after a specified time

            Returns:
                id of newly assigned request

            Throws:
                NoMoreRequests if the pool of active requests is full

        ***********************************************************************/

        public RequestId get ( Options ... ) ( cstring channel, hash_t key,
            Get.Notifier notifier, Options options )
        {
            auto params = Const!(Internals.Get.UserSpecifiedParams)(
                Const!(Get.Args)(channel, key),
                Const!(Internals.Get.UserSpecifiedParams.SerializedNotifier)(
                    *(cast(Const!(ubyte[notifier.sizeof])*)&notifier)
                )
            );

            auto id = this.assign!(Internals.Get)(params);

            setupOptionalArgs!(options.length)(options,
                ( Get.Timeout timeout )
                {
                    this.connections.request_set.setRequestTimeout(
                        id, timeout.ms);
                }
            );

            return id;
        }

        /***********************************************************************

            Assigns a Mirror request, reading updates from the specified
            channel.
            See $(LINK2 dhtproto/client/request/Mirror.html, dhtproto.client.request.Mirror)
            for detailed documentation.

            Params:
                Options = tuple of types of additional arguments
                channel = name of the channel to receive updates from
                notifier = notifier delegate
                options = additional arguments. The following are supported:
                    dhtproto.client.request.Mirror.Settings: Mirror behaviour
                        configuration

            Returns:
                id of newly assigned request

            Throws:
                NoMoreRequests if the pool of active requests is full

        ***********************************************************************/

        public RequestId mirror ( Options ... ) ( cstring channel,
            Mirror.Notifier notifier, Options options )
        {
            Mirror.Settings settings;

            setupOptionalArgs!(options.length)(options,
                ( Mirror.Settings user_settings )
                {
                    settings = user_settings;
                }
            );

            auto params = Const!(Internals.Mirror.UserSpecifiedParams)(
                Const!(Mirror.Args)(
                    channel,
                    settings
                ),
                Const!(Internals.Mirror.UserSpecifiedParams.SerializedNotifier)(
                    *(cast(Const!(ubyte[notifier.sizeof])*)&notifier)
                )
            );

            auto id = this.assign!(Internals.Mirror)(params);
            return id;
        }

        /***********************************************************************

            Assigns a GetAll request, reading all records from the specified
            channel.
            See $(LINK2 dhtproto/client/request/GetAll.html, dhtproto.client.request.GetAll)
            for detailed documentation.

            Params:
                Options = tuple of types of additional arguments
                channel = name of the channel to read from
                notifier = notifier delegate
                options = additional arguments. The following are supported:
                    dhtproto.client.request.GetAll.Settings: GetAll behaviour
                        configuration

            Returns:
                id of newly assigned request

            Throws:
                NoMoreRequests if the pool of active requests is full

        ***********************************************************************/

        public RequestId getAll ( Options ... ) ( cstring channel,
            GetAll.Notifier notifier, Options options )
        {
            GetAll.Settings settings;

            setupOptionalArgs!(options.length)(options,
                ( GetAll.Settings user_settings )
                {
                    settings = user_settings;
                }
            );

            auto params = Const!(Internals.GetAll.UserSpecifiedParams)(
                Const!(GetAll.Args)(
                    channel,
                    settings
                ),
                Const!(Internals.GetAll.UserSpecifiedParams.SerializedNotifier)(
                    *(cast(Const!(ubyte[notifier.sizeof])*)&notifier)
                )
            );

            auto id = this.assign!(Internals.GetAll)(params);
            return id;
        }

        /***********************************************************************

            Assigns a GetChannels request, reading the names of all channels in
            the DHT.
            See $(LINK2 dhtproto/client/request/GetChannels.html, dhtproto.client.request.GetChannels)
            for detailed documentation.

            Params:
                notifier = notifier delegate

            Returns:
                id of newly assigned request

            Throws:
                NoMoreRequests if the pool of active requests is full

        ***********************************************************************/

        public RequestId getChannels ( GetChannels.Notifier notifier )
        {
            auto params = Const!(Internals.GetChannels.UserSpecifiedParams)(
                Const!(GetChannels.Args)(),
                Const!(Internals.GetChannels.UserSpecifiedParams.SerializedNotifier)(
                    *(cast(Const!(ubyte[notifier.sizeof])*)&notifier)
                )
            );

            auto id = this.assign!(Internals.GetChannels)(params);
            return id;
        }

        /***********************************************************************

            Gets the type of the wrapper struct of the request associated with
            the specified controller interface.

            Params:
                I = type of controller interface

            Evaluates to:
                the type of the request wrapper struct which contains an
                implementation of the interface I

        ***********************************************************************/

        private template Request ( I )
        {
            static if ( is(I == Mirror.IController ) )
            {
                alias Internals.Mirror Request;
            }
            else static if ( is(I == GetAll.IController ) )
            {
                alias Internals.GetAll Request;
            }
            else
            {
                static assert(false, I.stringof ~ " does not match any request "
                    ~ "controller");
            }
        }

        /***********************************************************************

            Gets access to a controller for the specified request. If the
            request is still active, the controller is passed to the provided
            delegate for use.

            Important usage notes:
                1. The controller is newed on the stack. This means that user
                   code should never store references to it -- it must only be
                   used within the scope of the delegate.
                2. As the id which identifies the request is only known at run-
                   time, it is not possible to statically enforce that the
                   specified ControllerInterface type matches the request. This
                   is asserted at run-time, though (see
                   RequestSet.getRequestController()).

            Params:
                ControllerInterface = type of the controller interface (should
                    be inferred by the compiler)
                id = id of request to get a controller for (the return value of
                    the method which assigned your request)
                dg = delegate which is called with the controller, if the
                    request is still active

            Returns:
                false if the specified request no longer exists; true if the
                controller delegate was called

        ***********************************************************************/

        public bool control ( ControllerInterface ) ( RequestId id,
            void delegate ( ControllerInterface ) dg )
        {
            alias Request!(ControllerInterface) R;

            return this.controlImpl!(R)(id, dg);
        }

        /***********************************************************************

            Test instantiating the `control` function template.

        ***********************************************************************/

        unittest
        {
            alias control!(Mirror.IController) mirrorControl;
            alias control!(GetAll.IController) getAllControl;
        }

        /***********************************************************************

            Assigns a GetHashRange request. This request has no public API and
            cannot be assigned by the user. It is assigned automatically in the
            `neoInit` method of the outer class.

        ***********************************************************************/

        private void assignGetHashRange ( )
        {
            Internals.GetHashRange.UserSpecifiedParams params;
            this.assign!(Internals.GetHashRange)(params);
        }
    }

    /***************************************************************************

        Class wrapping access to all task-blocking "neo" features. (This
        functionality is separated from the main neo functionality as it
        implements methods with the same names and arguments (e.g. a callback-
        based Put request and a task-blocking Put request).)

    ***************************************************************************/

    public class TaskBlocking
    {
        import swarm.neo.client.mixins.TaskBlockingCore;
        import ocean.core.Array : copy;

        mixin TaskBlockingCore!();

        /***********************************************************************

            Suspends the current Task until a connection has been established to
            all known nodes and their hash-ranges queried.

        ***********************************************************************/

        public void waitAllHashRangesKnown ( )
        {
            auto task = Task.getThis();
            assert(task, "This method may only be called from inside a Task");

            auto old_user_conn_notifier = this.outer.user_conn_notifier;

            void conn_notifier ( Neo.DhtConnNotification info )
            {
                old_user_conn_notifier(info);

                with ( info.Active ) switch ( info.active )
                {
                    case hash_range_queried:
                        if ( task.suspended() )
                            task.resume();
                        break;

                    case connected:
                    case connection_error:
                        break;

                    default: assert(false);
                }
            }

            this.outer.user_conn_notifier = &conn_notifier;
            scope ( exit )
                this.outer.user_conn_notifier = old_user_conn_notifier;

            scope stats = this.outer.neo.new DhtStats;

            while ( stats.num_nodes_known_hash_range < stats.num_registered_nodes )
                task.suspend();
        }

        /***********************************************************************

            Task class which ensures that the hash ranges of all nodes are
            known. Intended for use with Scheduler.await() or
            Scheduler.awaitResult().

        ***********************************************************************/

        public class AllHashRangesKnown : Task
        {
            /*******************************************************************

                Task main method. Exits when the client has received the hash
                ranges of all registered nodes.

            *******************************************************************/

            public override void run ( )
            {
                this.outer.waitAllHashRangesKnown();
            }
        }

        /***********************************************************************

            Task class which ensures that the hash ranges of at least the
            specified number of nodes are known. Intended for use with
            Scheduler.await() or Scheduler.awaitResult().

        ***********************************************************************/

        public class HashRangesKnown : Task
        {
            /// When the task exits, holds the number of nodes whose hash ranges
            /// are known.
            public size_t result;

            /// The minimum number of node hash ranges to wait for.
            private size_t minimum_hr_known;

            /*******************************************************************

                Constructor.

                Params:
                    minimum_hr_known = the minimum number of node hash ranges to
                        wait for

            *******************************************************************/

            public this ( size_t minimum_hr_known )
            {
                this.minimum_hr_known = minimum_hr_known;
            }

            /*******************************************************************

                Task main method. Exits only when the client has received the
                hash ranges for at least this.minimum_hr_known nodes.

            *******************************************************************/

            public override void run ( )
            {
                scope stats = this.outer.outer.neo.new DhtStats;

                bool finished ( )
                {
                    return stats.num_nodes_known_hash_range >=
                        this.minimum_hr_known;
                }

                this.outer.waitConnect(&finished);

                this.result = stats.num_nodes_known_hash_range;
            }
        }

        /***********************************************************************

            Assigns a Put request and blocks the current Task until the request
            is completed. See
            $(LINK2 dhtproto/client/request/Put.html, dhtproto.client.request.Put)
            for detailed documentation.

            Params:
                channel = name of the channel to write to
                key = hash of the record to write
                value = record value to write (will be copied internally)
                user_notifier = notifier delegate

        ***********************************************************************/

        public void put ( cstring channel, hash_t key, Const!(void)[] value,
            Neo.Put.Notifier user_notifier )
        in
        {
            assert(user_notifier !is null);
        }
        body
        {
            auto task = Task.getThis();
            assert(task, "This method may only be called from inside a Task");

            bool finished;

            void notifier ( Neo.Put.Notification info, Neo.Put.Args args )
            {
                user_notifier(info, args);

                // All Put notifications indicate that the request has finished
                // (no need to switch)
                finished = true;
                if ( task.suspended )
                    task.resume();
            }

            this.outer.neo.put(channel, key, value, &notifier);
            if ( !finished ) // if request not completed, suspend
                task.suspend();
            assert(finished);
        }

        /***********************************************************************

            Struct returned after a Put request has finished.

        ***********************************************************************/

        private static struct PutResult
        {
            /*******************************************************************

                Set to true if the record was written to the DHT or false if an
                error occurred.

            *******************************************************************/

            bool succeeded;
        }

        /***********************************************************************

            Assigns a Put request and blocks the current Task until the request
            is completed. See
            $(LINK2 dhtproto/client/request/Put.html, dhtproto.client.request.Put)
            for detailed documentation.

            Note that the API of this method is intentionally minimal (e.g. it
            provides no detailed feedback about errors to the user). If you need
            more control, use the method above which works via a notifier
            callback.

            Params:
                channel = name of the channel to write to
                key = hash of the record to write
                value = record value to write (will be copied internally)

            Returns:
                PutResult struct, indicating the result of the request

        ***********************************************************************/

        public PutResult put ( cstring channel, hash_t key, Const!(void)[] value )
        {
            auto task = Task.getThis();
            assert(task, "This method may only be called from inside a Task");

            enum FinishedStatus
            {
                None,
                Succeeded,
                Failed
            }

            FinishedStatus state;

            void notifier ( Neo.Put.Notification info, Neo.Put.Args args )
            {
                with ( info.Active ) switch ( info.active )
                {
                    case success:
                        state = state.Succeeded;
                        if ( task.suspended )
                            task.resume();
                        break;

                    case value_too_big:
                    case node_disconnected:
                    case node_error:
                    case unsupported:
                    case no_node:
                    case wrong_node:
                    case failure:
                        state = state.Failed;
                        if ( task.suspended )
                            task.resume();
                        break;

                    default: assert(false);
                }
            }

            this.outer.neo.put(channel, key, value, &notifier);
            if ( state == state.None ) // if request not completed, suspend
                task.suspend();
            assert(state != state.None);

            PutResult res;
            res.succeeded = state == state.Succeeded;
            return res;
        }

        /***********************************************************************

            Assigns a Get request and blocks the current Task until the request
            is completed. See
            $(LINK2 dhtproto/client/request/Get.html, dhtproto.client.request.Get)
            for detailed documentation.

            Params:
                channel = name of the channel to read from
                key = hash of the record to read
                user_notifier = notifier delegate

        ***********************************************************************/

        public void get ( cstring channel, hash_t key,
            Neo.Get.Notifier user_notifier )
        in
        {
            assert(user_notifier !is null);
        }
        body
        {
            auto task = Task.getThis();
            assert(task, "This method may only be called from inside a Task");

            bool finished;

            void notifier ( Neo.Get.Notification info, Neo.Get.Args args )
            {
                user_notifier(info, args);

                // All Get notifications indicate that the request has finished
                // (no need to switch)
                finished = true;
                if ( task.suspended )
                    task.resume();
            }

            this.outer.neo.get(channel, key, &notifier);
            if ( !finished ) // if request not completed, suspend
                task.suspend();
            assert(finished);
        }

        /***********************************************************************

            Struct returned after a Get request has finished.

        ***********************************************************************/

        private static struct GetResult
        {
            /*******************************************************************

                Set to true if no error occurred.

            *******************************************************************/

            bool succeeded;

            /*******************************************************************

                The value read from the channel or an empty array, if no record
                exists in the channel for the specified key or an error
                occurred.

            *******************************************************************/

            void[] value;
        }

        /***********************************************************************

            Assigns a Get request and blocks the current Task until the request
            is completed. See
            $(LINK2 dhtproto/client/request/Get.html, dhtproto.client.request.Get)
            for detailed documentation.

            Note that the API of this method is intentionally minimal (e.g. it
            provides no detailed feedback about errors to the user). If you need
            more control, use the method above which works via a notifier
            callback.

            Params:
                channel = name of the channel to read from
                key = hash of the record to read
                value = buffer to receive the read value (will be set to length
                    0, if key does not exists in the specified channel)

            Returns:
                GetResult struct, indicating the result of the request

        ***********************************************************************/

        public GetResult get ( cstring channel, hash_t key, ref void[] value )
        {
            auto task = Task.getThis();
            assert(task, "This method may only be called from inside a Task");

            enum FinishedStatus
            {
                None,
                Succeeded,
                Failed
            }

            GetResult res;
            FinishedStatus state;

            void notifier ( Neo.Get.Notification info, Neo.Get.Args args )
            {
                with ( info.Active ) switch ( info.active )
                {
                    case received:
                        value.copy(info.received.value);
                        res.value = value;
                        goto case no_record;

                    case no_record:
                        state = state.Succeeded;
                        if ( task.suspended )
                            task.resume();
                        break;

                    case node_disconnected:
                    case node_error:
                    case unsupported:
                    case no_node:
                    case wrong_node:
                    case failure:
                        state = state.Failed;
                        if ( task.suspended )
                            task.resume();
                        break;

                    default: assert(false);
                }
            }

            this.outer.neo.get(channel, key, &notifier);
            if ( state == state.None ) // if request not completed, suspend
                task.suspend();
            assert(state != state.None);

            res.succeeded = state == state.Succeeded;
            return res;
        }

        /***********************************************************************

            Struct to provide an opApply for a task-blocking GetAll.

            Node that the Task-blocking GetAll consciously provides a
            simplistic, clean API, without any of the more advanced features of
            the request (e.g. suspending). If you need these features, please
            use the standard, callback-based version of the request.

        ***********************************************************************/

        public struct GetAllFruct
        {
            import ocean.core.array.Mutation: copy;

            /// User task to resume/suspend.
            private Task task;

            /// Key of the current record.
            private hash_t record_key;

            /// Value of the current record.
            private void[]* record_value;

            /// Possible states of the request.
            private enum State
            {
                /// The request is running.
                Running,

                /// The user has stopped this request by breaking from foreach
                /// (the request may still be running for some time, but all
                /// records will be ignored).
                Stopped,

                /// The request has finished on all nodes.
                Finished
            }

            /// Indicator of the request's state.
            private State state;

            /// Channel to iterate over.
            private cstring channel;

            /// Neo instance to assign the request with.
            private Neo neo;

            /// Error indicator.
            public bool error;

            /// Request id (used internally).
            private Neo.RequestId rq_id;

            /*******************************************************************

                Notifier used to set the local values and resume the task.

                Params:
                    info = information and payload about the event user has
                        been notified about
                    args = arguments passed by the user when starting request

            *******************************************************************/

            private void notifier ( Neo.GetAll.Notification info,
                Neo.GetAll.Args args )
            {
                with ( info.Active ) switch ( info.active )
                {
                    case received:
                        // Ignore all received value on user break.
                        if (this.state == State.Stopped)
                            break;

                        // Store the received value.
                        this.record_key = info.received.key;

                        copy(*this.record_value, info.received.value);

                        if (this.task.suspended())
                        {
                            this.task.resume();
                        }
                        break;

                    case stopped:
                    case finished:
                        // Even if the user has requested stopping,
                        // but finished arrived, we will just finish and exit.
                        this.state = State.Finished;
                        this.task.resume();
                        break;

                    case node_disconnected:
                    case node_error:
                    case unsupported:
                        // Ignore all errors on user break.
                        if (this.state == State.Stopped)
                            break;

                        // Otherwise flag an error and finish.
                        this.state = State.Finished;
                        this.error = true;
                        this.task.resume();
                        break;

                    case received_key:
                        // Not yet supported by blocking GetAll.
                        break;

                    case started:
                        // Irrelevant.
                        break;

                    default: assert(false);
                }
            }

            /*******************************************************************

                Task-blocking opApply iteration over GetAll.

            *******************************************************************/

            public int opApply ( int delegate ( ref hash_t key,
                ref void[] value ) dg )
            {
                int ret;

                this.rq_id = this.neo.getAll(this.channel, &this.notifier);

                while (this.state != State.Finished)
                {
                    Task.getThis().suspend();

                    // No more records.
                    if (this.state == State.Finished
                            || this.state == State.Stopped
                            || this.error)
                        break; 

                    ret = dg(this.record_key, *this.record_value);

                    if (ret)
                    {
                        this.state = State.Stopped;

                        this.neo.control(this.rq_id,
                            ( Neo.GetAll.IController get_all )
                            {
                                get_all.stop();
                            });

                        // Wait for the request to finish.
                        Task.getThis().suspend();
                        break;
                    }
                }

                return ret;
            }
        }

        /***********************************************************************

            Assigns a task blocking GetAll request, getting the values from
            the specified channel and range. This method provides nothing but
            the most basic usage (no request context, no way to control the
            request (stop/resume/suspend)), so if that is needed, please use the
            non-task blocking getAll.

            Breaking out of the iteration stops the GetAll request.

            Params:
                channel = name of the channel to get the records from
                record_buffer = reusable buffer to store the current record's
                    values into

            Returns:
                GetAllFruct structure, whose opApply should be used

        ***********************************************************************/

        public GetAllFruct getAll ( cstring channel, ref void[] record_buffer )
        {
            auto task = Task.getThis();
            assert(task !is null,
                    "This method may only be called from inside a Task");

            GetAllFruct res;
            res.task = task;
            res.neo = this.outer.neo;
            res.record_value = &record_buffer;
            res.channel = channel;

            return res;
        }

        /***********************************************************************

            Struct to provide an opApply for a task-blocking GetChannels.

        ***********************************************************************/

        public struct GetChannelsFruct
        {
            import ocean.core.array.Mutation: copy;

            /// User task to resume/suspend.
            private Task task;

            /// Name of the current channel.
            private mstring* channel_name;

            /// Possible states of the request.
            private enum State
            {
                /// The request is running.
                Running,

                /// The user has stopped this request by breaking from foreach
                /// (the request may still be running for some time, but all
                /// channel names will be ignored).
                Stopped,

                /// The request has finished on all nodes.
                Finished
            }

            /// Indicator of the request's state.
            private State state;

            /// Neo instance to assign the request with.
            private Neo neo;

            /// Error indicator.
            public bool error;

            /*******************************************************************

                Notifier used to set the local values and resume the task.

                Params:
                    info = information and payload about the event user has
                        been notified about
                    args = arguments passed by the user when starting request

            *******************************************************************/

            private void notifier ( Neo.GetChannels.Notification info,
                Neo.GetChannels.Args args )
            {
                with ( info.Active ) switch ( info.active )
                {
                    case received:
                        // Ignore all received value on user break.
                        if (this.state == State.Stopped)
                            break;

                        copy(*this.channel_name,
                            cast(cstring)info.received.value);

                        if (this.task.suspended())
                        {
                            this.task.resume();
                        }
                        break;

                    case finished:
                        this.state = State.Finished;
                        this.task.resume();
                        break;

                    case node_disconnected:
                    case node_error:
                    case unsupported:
                        // Ignore all errors on user break.
                        if (this.state == State.Stopped)
                            break;

                        // Otherwise flag an error and finish.
                        this.state = State.Finished;
                        this.error = true;
                        this.task.resume();
                        break;

                    default: assert(false);
                }
            }

            /*******************************************************************

                Task-blocking opApply iteration over GetChannels.

            *******************************************************************/

            public int opApply ( int delegate ( ref mstring channel_name ) dg )
            {
                int ret;

                this.neo.getChannels(&this.notifier);

                while (this.state != State.Finished)
                {
                    Task.getThis().suspend();

                    // No more records.
                    if (this.state == State.Finished
                            || this.state == State.Stopped
                            || this.error)
                        break; 

                    ret = dg(*this.channel_name);

                    if (ret)
                    {
                        this.state = State.Stopped;

                        // Wait for the request to finish.
                        Task.getThis().suspend();
                        break;
                    }
                }

                return ret;
            }
        }

        /***********************************************************************

            Assigns a task blocking GetChannels request, getting the channel
            names from the DHT.

            Params:
                channel_buffer = reusable buffer to store the current channel's
                    name in

            Returns:
                GetChannelsFruct structure, whose opApply should be used

        ***********************************************************************/

        public GetChannelsFruct getChannels ( ref mstring channel_buffer )
        {
            auto task = Task.getThis();
            assert(task !is null,
                    "This method may only be called from inside a Task");

            GetChannelsFruct res;
            res.task = task;
            res.neo = this.outer.neo;
            res.channel_name = &channel_buffer;

            return res;
        }
    }

    /***************************************************************************

        Object containing all neo functionality.

    ***************************************************************************/

    public Neo neo;

    /***************************************************************************

        Object containing all neo task-blocking functionality.

    ***************************************************************************/

    public TaskBlocking blocking;

    /***************************************************************************

        Global resources required by all requests. Passed to the ConnectionSet.

    ***************************************************************************/

    private SharedResources shared_resources;

    /***************************************************************************

        Callback for notifying the user about connection success / failure and
        hash-range queries.

    ***************************************************************************/

    private Neo.DhtConnectionNotifier user_conn_notifier;

    /***************************************************************************

        Helper function to initialise neo components. Automatically calls
        addNodes() with the node definition files specified in the Config
        instance.

        Params:
            config = swarm.client.model.IClient.Config instance. (The Config
                class is designed to be read from an application's config.ini
                file via ocean.util.config.ConfigFiller.)
            conn_notifier = delegate which is called when a connection attempt
                succeeds or fails (including when a connection is
                re-established) and when the hash-range for a node is first
                queried. Of type:
                void delegate ( Neo.DhtConnNotification )

    ***************************************************************************/

    private void neoInit ( Neo.Config config,
        Neo.DhtConnectionNotifier user_conn_notifier )
    in
    {
        assert(user_conn_notifier !is null);
    }
    body
    {
        this.user_conn_notifier = user_conn_notifier;

        this.shared_resources = new SharedResources;
        this.neo = new Neo(config,
            Neo.Settings(&this.connNotifier, this.shared_resources));
        auto node_hash_ranges = new NodeHashRanges(this.neo.connections,
            &this.hashRangeNotifier);
        this.shared_resources.setNodeHashRanges(node_hash_ranges);
        this.blocking = new TaskBlocking;

        this.neo.assignGetHashRange();
    }

    /***************************************************************************

        Helper function to initialise neo components. This initialiser that
        accepts all arguments manually (i.e. not read from config files) is
        mostly of use in tests.

        Params:
            auth_name = client name for authorisation
            auth_key = client key (password) for authorisation. This should be a
                properly generated random number which only the client and the
                nodes know. See `swarm/README_client_neo.rst` for suggestions.
                The key must be of the length defined in
                swarm.neo.authentication.HmacDef (128 bytes)
            conn_notifier = delegate which is called when a connection attempt
                succeeds or fails (including when a connection is
                re-established) and when the hash-range for a node is first
                queried. Of type:
                void delegate ( Neo.DhtConnNotification )

    ***************************************************************************/

    private void neoInit ( cstring auth_name, ubyte[] auth_key,
        Neo.DhtConnectionNotifier user_conn_notifier )
    in
    {
        assert(user_conn_notifier !is null);
    }
    body
    {
        this.user_conn_notifier = user_conn_notifier;

        this.shared_resources = new SharedResources;
        this.neo = new Neo(auth_name, auth_key,
            Neo.Settings(&this.connNotifier, this.shared_resources));
        auto node_hash_ranges = new NodeHashRanges(this.neo.connections,
            &this.hashRangeNotifier);
        this.shared_resources.setNodeHashRanges(node_hash_ranges);
        this.blocking = new TaskBlocking;

        this.neo.assignGetHashRange();
    }

    /***************************************************************************

        Neo client connection notifier. Calls this.user_conn_notifier as
        appropriate.

        Params:
            addr = address of node for which connection succeeded / failed
            e = exception. If null, the connection succeeded. Otherwise,
                indicates the error which prevented connection

    ***************************************************************************/

    private void connNotifier ( Neo.ConnNotification info )
    {
        Neo.DhtConnNotification n;
        with ( info.Active ) switch ( info.active )
        {
            case connected:
                n.connected = NodeInfo(info.connected.node_addr);
                break;
            case error_while_connecting:
                n.connection_error = NodeExceptionInfo(
                    info.error_while_connecting.node_addr,
                    info.error_while_connecting.e);
                break;
            default:
                assert(false);
        }

        this.user_conn_notifier(n);
    }

    /***************************************************************************

        NodeHashRanges new node notifier. Calls this.user_conn_notifier as
        appropriate.

        Params:
            addr = address of node for which hash-range info has been queried
            min = minimum hash covered by node
            max = maximum hash covered by node

    ***************************************************************************/

    private void hashRangeNotifier ( AddrPort addr, hash_t min, hash_t max )
    {
        Neo.DhtConnNotification n;
        n.hash_range_queried = NodeInfo(addr);

        this.user_conn_notifier(n);
    }
}
