/*******************************************************************************

    Client DHT Get request definitions / handler.

    The Get request attempts to read one record from the specified DHT channel.
    This works as follows:
        1. The client selects a connected DHT node from its registry, based on
           the key of the record to be read.
        2. A request is sent to the selected node, asking for the specified
           record in the specified channel to be returned.
        3. The request ends when either the record is read from the node or the
           node could not handle the request due to an error.

    During a data redistribution, more than one node may be responsible for a
    given key. In this case, the node which was most recently reported as being
    responsible for the key is queried first, followed by others (in order)
    until the record is located, an error occurs, or no node has the record.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.Get;

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
}

/*******************************************************************************

    Optional struct to be passed when assigning a Get request. Specifies that
    the request should time out after the specified period, if it has not
    completed.

*******************************************************************************/

public struct Timeout
{
    /// Timeout in milliseconds.
    uint ms;
}

/*******************************************************************************

    Union of possible notifications.

*******************************************************************************/

private union NotificationUnion
{
    /// The request succeeded, but no record exists with the specified key.
    RequestInfo no_record;

    /// The request succeeded and the value was read.
    RequestDataInfo received;

    /// The request timed out before it completed.
    RequestInfo timed_out;

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
