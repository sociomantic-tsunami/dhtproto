/*******************************************************************************

    Client DHT Put request definitions / handler.

    The Put request attempts to write one record to the specified DHT channel.
    This works as follows:
        1. The client selects a connected DHT node from its registry, based on
           the key of the record to put.
        2. A request is sent to the selected node, asking for the specified
           record to be added to the specified channel.
        3. The request ends when either the record is pushed to the node or the
           node could not handle the request due to an error.

    During a data redistribution, more than one node may be responsible for a
    given key. In this case, the record is written to the node which was most
    recently reported as being responsible for the key.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.Put;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;
import ocean.core.SmartUnion;
public import swarm.neo.client.NotifierTypes;

/*******************************************************************************

    Request-specific arguments provided by the user and passed to the notifier.

*******************************************************************************/

public struct Args
{
    mstring channel;
    hash_t key;
    void[] value;
}

/*******************************************************************************

    Union of possible notifications.

*******************************************************************************/

private union NotificationUnion
{
    /// The request succeeded.
    RequestInfo success;

    /// The request failed due to a connection error.
    RequestNodeExceptionInfo node_disconnected;

    /// The request failed due to an internal node error.
    RequestNodeInfo node_error;

    /// The request failed because it is unsupported.
    RequestNodeUnsupportedInfo unsupported;

    /// The DHT node to which the request was sent is not responsible for the
    /// record's key. This is a sanity check performed within the node in order
    /// to avoid data inconsistency.
    RequestNodeInfo wrong_node;

    /// No DHT node is known to cover the hash of the request. Note that this
    /// may be because the client has just been started and has not received
    /// hash range information from the DHT yet.
    RequestInfo no_node;

    /// Internal error in client.
    RequestInfo failure;
}

/*******************************************************************************

    Notification smart union.

*******************************************************************************/

public alias SmartUnion!(NotificationUnion) Notification;

/*******************************************************************************

    Type of notifcation delegate.

*******************************************************************************/

public alias void delegate ( Notification, Args ) Notifier;
