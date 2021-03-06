/*******************************************************************************

    Request resource acquirer.

    Via an instance of this interface, a request is able to acquire different
    types of resource which it requires during its lifetime.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.core.IRequestResources;

public interface IRequestResources
{
    import swarm.neo.request.RequestEventDispatcher;
    import swarm.neo.util.MessageFiber;
    import swarm.util.RecordBatcher;
    import ocean.io.compress.Lzo;

    /***************************************************************************

        Returns:
            a shared LZO instance

    ***************************************************************************/

    Lzo lzo ( );


    /***************************************************************************

        Returns:
            a pointer to a new chunk of memory (a void[]) to use during the
            request's lifetime

    ***************************************************************************/

    void[]* getVoidBuffer ( );

    /***************************************************************************

        Gets a fiber to use during the request's lifetime and assigns the
        provided delegate as its entry point.

        Params:
            fiber_method = entry point to assign to acquired fiber

        Returns:
            a new MessageFiber acquired to use during the request's lifetime

    ***************************************************************************/

    MessageFiber getFiber ( scope void delegate ( ) fiber_method );

    /***************************************************************************

        Gets a record batcher to use during the request's lifetime.

        Returns:
            a new record batcher acquired to use during the request's lifetime

    ***************************************************************************/

    RecordBatcher getRecordBatcher ( );

    /***************************************************************************

        Gets a periodically firing timer.

        Params:
            period_s = seconds part of timer period
            period_ms = milliseconds part of timer period
            timer_dg = delegate to call when timer fires

        Returns:
            ITimer interface to a timer to use during the request's lifetime

    ***************************************************************************/

    ITimer getTimer ( uint period_s, uint period_ms, scope void delegate ( ) timer_dg );

    /***************************************************************************

        Interface to a timer to be used during the request's lifetime.

    ***************************************************************************/

    interface ITimer
    {
        /// Starts the timer.
        void start ( );

        /// Stops the timer.
        void stop ( );
    }
}
