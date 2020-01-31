/*******************************************************************************

    Client DHT Remove request definitions / handler.

    The Remove request attempts to remove one record from the specified DHT
    channel. This works as follows:
        1. The client selects a connected DHT node from its registry, based on
           the key of the record to be read.
        2. A request is sent to the selected node, asking for the specified
           record in the specified channel to be removed.
        3. The request ends when either the record is removed from the node, is
           found to not exist, or the node could not handle the request due to
           an error.

    During a data redistribution, more than one node may be responsible for a
    given key. In this case, the node that was least recently reported as being
    responsible for the key is queried first, followed by others (in order)
    until the record is either removed from or does not exist on all nodes, or
    an error occurs. The reason for removing from the *least* recently
    responsible nodes first is to avoid getting into inconsistent states if an
    error occurs while removing. (If an error occurred when removing the record
    from the most recently responsible node first, subsequent read requests
    would fetch the removed record from older nodes, and the old value could be
    forwarded from an older node, undoing the removal.)

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.Remove;

import ocean.meta.types.Qualifiers;
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

    Union of possible notifications.

    The following notifications are considered fatal (i.e. the request will
    almost certainly get the same error if retried):
    * node_error
    * unsupported
    * wrong_node

*******************************************************************************/

private union NotificationUnion
{
    /// The request succeeded; no record existed with the specified key.
    RequestInfo no_record;

    /// The request succeeded and the record was removed.
    RequestInfo removed;

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

public alias void delegate ( Notification, const(Args) ) Notifier;
