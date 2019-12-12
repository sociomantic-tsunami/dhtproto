/*******************************************************************************

    Tracker for availability of nodes, based on recency of connection errors.

    This helper is useful in apps that have a data flow pattern like the
    following:
        1. Receive a record from an incoming source (e.g. a DMQ channel).
        2. Do some expensive but non-critical processing on the record. (e.g.
           querying an external service.)
        3. Write the results of the processing to the DHT.

    By tracking which DHT nodes have had connectivity problems recently, the app
    can decide to not perform step 2 at all, if the DHT node to which the result
    would be written is inaccessible. (i.e. discarding the request, rather than
    queuing up the write to be performed when the DHT node becomes accessible.)

    Copyright:
        Copyright (c) 2018 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.helper.NodeAvailability;

/// ditto
public struct NodeAvailabilty
{
    import swarm.Const;
    import core.sys.posix.time;
    import dhtproto.client.legacy.internal.registry.model.IDhtNodeRegistryInfo;

    /// The number of seconds for which the `available()` methods will report a
    /// node as inaccessible after an error is reported for it.
    public uint retry_delay_s = 3;

    /***************************************************************************

        Should be called when a request to the specified node fails due to a
        connection error.

        Params:
            node = node that had a connection error

    ***************************************************************************/

    public void error ( NodeItem node )
    {
        if ( auto tracker = node.toHash() in this.error_trackers )
        {
            tracker.error();
        }
        else
        {
            auto tracker = NodeErrorTracker(&this);
            tracker.error();
            this.error_trackers[node.toHash()] = tracker;
        }
    }

    /***************************************************************************

        Tells whether the node that is responsible for the specified key is
        believed to be currently accessible or not.

        Params:
            key = key of record to be accessed
            registry = node registry to look up which node is responsible for
                the specified key

        Returns:
            true if the node is believed to be accessible; false if it has had a
            connection error recently

    ***************************************************************************/

    public bool available ( hash_t key, IDhtNodeRegistryInfo registry )
    {
        auto node = registry.responsibleNode(key);
        if ( node is null )
            return false;

        NodeItem nodeitem;
        nodeitem.Address = node.address;
        nodeitem.Port = node.port;

        return available(nodeitem);
    }

    /***************************************************************************

        Tells whether the specified node is believed to be currently accessible
        or not.

        Params:
            node = node to be accessed

        Returns:
            true if the node is believed to be accessible; false if it has had a
            connection error recently

    ***************************************************************************/

    public bool available ( NodeItem node )
    {
        if ( auto tracker = node.toHash() in this.error_trackers )
            return tracker.available();
        else
            return true;
    }

    /// Internal error tracker for a single node.
    private struct NodeErrorTracker
    {
        /// Pointer to the outer instance.
        NodeAvailabilty* outer;

        /// Timestamp of last reported connection error.
        private time_t last_error_timestamp;

        /***********************************************************************

            Should be called when a request to this node fails due to a
            connection error.

        ***********************************************************************/

        public void error ( )
        {
            this.last_error_timestamp = time();
        }

        /***********************************************************************

            Tells whether the node is believed to be currently accessible or
            not.

            Returns:
                true if the node is believed to be accessible; false if it has
                had a connection error recently

        ***********************************************************************/

        public bool available ( )
        {
            auto diff = time() - this.last_error_timestamp;
            return diff >= this.outer.retry_delay_s;
        }

        /***********************************************************************

            Returns:
                the current timestamp

        ***********************************************************************/

        private static time_t time ( )
        {
            timespec t;
            clock_gettime(CLOCK_MONOTONIC, &t);
            return t.tv_sec;
        }
    }

    /// Map of error trackers by node hash.
    private NodeErrorTracker[hash_t] error_trackers;
}

version ( unittest )
{
    import ocean.core.Test;
    import swarm.Const;
}

unittest
{
    auto n1 = NodeItem("addr".dup, 100);
    auto n2 = NodeItem("addr".dup, 200);
    NodeAvailabilty tracker;

    test(tracker.available(n1));
    test(tracker.available(n2));

    tracker.error(n1);
    test(!tracker.available(n1));
    test(tracker.available(n2));

    // Hack the last error timestamp so that it looks like the required delay
    // has expired. (This saves us having to actually wait.)
    tracker.error_trackers[n1.toHash].last_error_timestamp -=
        tracker.retry_delay_s;
    test(tracker.available(n1));
    test(tracker.available(n2));
}
