/*******************************************************************************

    Client DHT GetAll request definitions / handler.

    The GetAll request communicates with all DHT nodes to fetch all records in a
    channel. If a connection error occurs, the request will be restarted once
    the connection has been re-established and will continue from where it left
    off.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.GetAll;

import ocean.transition;
import ocean.core.SmartUnion;
public import swarm.neo.client.NotifierTypes;
public import dhtproto.client.NotifierTypes;

/*******************************************************************************

    GetAll behaviour settings. May be optionally passed to the getAll() method
    of the DHT client, to modify the default behaviour.

*******************************************************************************/

public struct Settings
{
    /// If true, only record keys will be fetched, no values.
    bool keys_only;

    /// If non-empty, only records whose values contain these bytes as a
    /// "substring" will be fetched.
    void[] value_filter;
}

/*******************************************************************************

    Request-specific arguments provided by the user and passed to the notifier.

*******************************************************************************/

public struct Args
{
    /// Name of the channel to fetch.
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
    /// records may be received from some nodes before this notification occurs.
    RequestInfo started;

    /// A record has been received from the DHT.
    RequestRecordInfo received;

    /// A record key has been received from the DHT. (Only used when in
    /// keys-only mode. See Settings.)
    RequestKeyInfo received_key;

    /// The connection to a node has disconnected; the request will
    /// automatically continue after reconnection.
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

    /// All known nodes have either finished the request or are not currently
    /// connected. The request is now finished.
    RequestInfo finished;
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

    /***************************************************************************

        Returns:
            `true` if the nde is suspended, otherwise, `false`.

    ***************************************************************************/

    bool suspended ( );
}
