/*******************************************************************************

    Client DHT Mirror request definitions / handler.

    The Mirror request communicates with all DHT nodes to fetch records from a
    whole channel (i.e. the request creates a "mirror" of the channel in the
    client). When a record is modified in the channel, an update is immediately
    sent to the client via the Mirror request. The request can also be
    configured to periodically perform a "refresh" on all records -- that is,
    fetch a copy of all records in the mirrored channel, irrespective of whether
    they've changed recently or not. Two options are possible here (usable in
    any combination):
        1. Initial refresh: when the request starts, all records in the channel
           are sent to the client via the Mirror request.
        2. Periodic refreshes: every N seconds (as specified by the user), all
           records in the channel are sent to the client via the Mirror request.

    The most common ways of using a Mirror request are:
        a. To get an initial dump of all records in a channel, followed by a
           stream of updates to records in the channel. (Refresh mode 1.)
        b. To get an initial dump of all records in a channel, followed by a
           stream of updates to records in the channel plus a periodic fresh
           dump of the values of all records (the latter as a fall-back, in case
           any errors occurred in transferring updates via the stream). (Refresh
           modes 1 and 2.) (This is the default behaviour of the request, if no
           settings are configured by the user.)

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.Mirror;

import ocean.transition;
import ocean.core.SmartUnion;
public import swarm.neo.client.NotifierTypes;
public import dhtproto.client.NotifierTypes;

/*******************************************************************************

    Mirror behaviour settings. May be optionally passed to the mirror() method
    of the DHT client, to modify the default behaviour.

    The Mirror request provides the possibility of two types of refresh which
    can be combined in various ways:
        1. Initial refresh: when the request starts, all records in the channel
           are sent to the client via the Mirror request.
        2. Periodic refreshes: every N seconds (as specified by the user), all
           records in the channel are sent to the client via the Mirror request.

*******************************************************************************/

public struct Settings
{
    /// If true, the request, upon starting, will immediately send all records
    /// in the channel to the client.
    bool initial_refresh = true;

    /// If non-zero, the request will repeatedly send all records in the channel
    /// to the client after every specified period. If zero, no periodic
    /// refreshes will occur.
    uint periodic_refresh_s = 360;
}

/*******************************************************************************

    Request-specific arguments provided by the user and passed to the notifier.

*******************************************************************************/

public struct Args
{
    /// Name of the channel to mirror.
    mstring channel;

    /// Settings for the behaviour of the request.
    Settings settings;
}

/*******************************************************************************

    Union of possible notifications.

    The following notifications are considered fatal (i.e. the request will
    almost certainly get the same error if retried):
    * node_error
    * unsupported

*******************************************************************************/

private union NotificationUnion
{
    /// The request is now in a state where it can be suspended / resumed /
    /// stopped via the controller. (This means that all known nodes have either
    /// started handling the request or are not currently connected.) Note that
    /// updates may be received from some nodes before this notification occurs.
    RequestInfo started;

    /// A record's value has been updated.
    RequestRecordInfo updated;

    /// A record's value has been resent to the client during a refresh cycle.
    RequestRecordInfo refreshed;

    /// A record has been removed.
    RequestKeyInfo deleted;

    /// The connection to a node disconnected; the request will automatically
    /// continue after reconnection.
    RequestNodeExceptionInfo node_disconnected;

    /// A node returned a non-OK status code. The request cannot be handled by
    /// this node.
    RequestNodeInfo node_error;

    /// The request was tried on a node and failed because it is unsupported.
    /// The request cannot be handled by this node.
    RequestNodeUnsupportedInfo unsupported;

    /// All known nodes have either suspended the request (as requested by the
    /// user, via the controller) or are not currently connected.
    RequestInfo suspended;

    /// All known nodes have either resumed the request (as requested by the
    /// user, via the controller) or are not currently connected.
    RequestInfo resumed;

    /// All known nodes have either stopped the request (as requested by the
    /// user, via the controller) or are not currently connected. The request is
    /// now finished. (A `finished` notification will not occur as well.)
    RequestInfo stopped;

    /// The channel being mirrored has been removed. The request is now
    /// finished for this node.
    RequestNodeInfo channel_removed;

    /// The queue of updates to be sent to the client from the specified node
    /// has overflowed. At least one update has been discarded.
    RequestNodeInfo updates_lost;
}

/*******************************************************************************

    Notification smart union.

*******************************************************************************/

public alias SmartUnion!(NotificationUnion) Notification;

/*******************************************************************************

    Type of notification delegate.

*******************************************************************************/

public alias void delegate ( Notification, Const!(Args) ) Notifier;

/*******************************************************************************

    Request controller, accessible via the client's `control()` method.

    Note that only one control change message can be "in-flight" to the nodes at
    a time. If the controller is used when a control change message is already
    in-flight, the method will return false. The notifier is called when a
    requested control change is carried through.

*******************************************************************************/

public interface IController
{
    /***************************************************************************

        Tells the nodes to stop sending data to this request.

        Returns:
            false if the controller cannot be used because a control change is
            already in progress

    ***************************************************************************/

    bool suspend ( );

    /***************************************************************************

        Tells the nodes to resume sending data to this request.

        Returns:
            false if the controller cannot be used because a control change is
            already in progress

    ***************************************************************************/

    bool resume ( );

    /***************************************************************************

        Tells the nodes to cleanly end the request.

        Returns:
            false if the controller cannot be used because a control change is
            already in progress

    ***************************************************************************/

    bool stop ( );
}
