/*******************************************************************************

    Fake DHT node neo request shared resources getter.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.neo.SharedResources;

import ocean.meta.types.Qualifiers;

import dhtproto.node.neo.request.core.IRequestResources;

/*******************************************************************************

    Provides resources required by the protocol. As this implementation is fpr
    testing purposes only, it simply allocates as much stuff as necessary to
    keep the code simple.

*******************************************************************************/

class SharedResources : IRequestResources
{
    import ocean.core.Verify;
    import ocean.io.compress.Lzo;
    import swarm.neo.util.MessageFiber;
    import swarm.util.RecordBatcher;

    /***************************************************************************

        Struct wrapper used to workaround D's inability to allocate slices on
        the heap via `new`.

    ***************************************************************************/

    private static struct Buffer
    {
        void[] data;
    }

    /***************************************************************************

        Returns:
            a shared LZO instance

    ***************************************************************************/

    override public Lzo lzo ( )
    {
        return new Lzo;
    }

    /***************************************************************************

        Returns:
            a new buffer to store record values in

    ***************************************************************************/

    override public void[]* getVoidBuffer ( )
    {
        return &((new Buffer).data);
    }

    /***************************************************************************

        Gets a fiber to use during the request's lifetime and assigns the
        provided delegate as its entry point.

        Params:
            fiber_method = entry point to assign to acquired fiber

        Returns:
            a new MessageFiber acquired to use during the request's lifetime

    ***************************************************************************/

    public MessageFiber getFiber ( scope void delegate ( ) fiber_method )
    {
        return new MessageFiber(fiber_method, 64 * 1024);
    }

    /***************************************************************************

        Gets a record batcher to use during the request's lifetime.

        Returns:
            a new record batcher acquired to use during the request's lifetime

    ***************************************************************************/

    public RecordBatcher getRecordBatcher ( )
    {
        return new RecordBatcher(new Lzo);
    }

    /***************************************************************************

        Gets a periodically firing timer.

        Params:
            period_s = seconds part of timer period
            period_ms = milliseconds part of timer period
            timer_dg = delegate to call when timer fires

        Returns:
            ITimer interface to a timer to use during the request's lifetime

    ***************************************************************************/

    public ITimer getTimer ( uint period_s, uint period_ms,
        scope void delegate ( ) timer_dg )
    {
        verify(period_ms < 1_000);
        verify(period_s > 0 || period_ms > 0);
        verify(timer_dg !is null);
        return new Timer(period_s, period_ms, timer_dg);
    }

    /***************************************************************************

        Timer to be used during the request's lifetime.

    ***************************************************************************/

    private class Timer : ITimer
    {
        import ocean.io.select.client.TimerEvent;
        import ocean.task.Scheduler;

        /// Flag set to true when the timer is running.
        private bool running;

        /// Timer event registered with epoll.
        private TimerEvent timer;

        // User's timer delegate.
        private void delegate ( ) timer_dg;

        /***********************************************************************

            Constructor.

            Params:
                period_s = seconds part of timer period
                period_ms = milliseconds part of timer period
                timer_dg = delegate to call when timer fires

        ***********************************************************************/

        private this ( uint period_s, uint period_ms, scope void delegate ( ) timer_dg )
        {
            this.timer_dg = timer_dg;
            this.timer = new TimerEvent(&this.timerDg);
            this.timer.set(period_s, period_ms, period_s, period_ms);
        }

        /***********************************************************************

            Starts the timer, registering it with epoll.

        ***********************************************************************/

        public void start ( )
        {
            this.running = true;
            theScheduler.epoll.register(this.timer);
        }

        /***********************************************************************

            Stops the timer, unregistering it from epoll.

        ***********************************************************************/

        public void stop ( )
        {
            this.running = false;
            theScheduler.epoll.unregister(this.timer);
        }

        /***********************************************************************

            Internal delegate called when timer fires. Calls the user's delegate
            and handles unregistering when stopped.

        ***********************************************************************/

        private bool timerDg ( )
        {
            this.timer_dg();
            return this.running;
        }
    }
}
