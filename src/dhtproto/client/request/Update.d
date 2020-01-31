/*******************************************************************************

    Client DHT Update request definitions / handler.

    The Update request attempts to read one record from the specified DHT
    channel and replace its value in the DHT with a modified version, specified
    by the user. This works as follows:
        1. The client selects a connected DHT node from its registry, based on
           the key of the record to be updated.
        2. A request is sent to the selected node, asking for the specified
           record in the specified channel to be returned.
        3. If the record exists, its value is passed to the user, who may
           provide a modified version of the value or decide to leave the value
           as it is.
        4. The modified version of the value is then sent back to the DHT. One
           of the following then happens:
            4a. The record has been modified by another request, in the
                meantime. The Update request is rejected and has no effect. (The
                user may retry the request.)
            4b. The record has either been removed of has not been modified, in
                the meantime. The new value is written to the DHT.
        5. The request ends when either the record does not exist, is
           successfully updated in the node, or the node could not handle the
           request due to an error.

    During a data redistribution, more than one node may be responsible for a
    given key. In this case, the following logic is used:
        * Reading: the node that was most recently reported as being responsible
          for the key is queried first, followed by others (in order) until the
          record is located, an error occurs, or no node has the record.
        * Updating: the modified record is written to the node that was most
          recently reported as being responsible for the key. If this is
          different to the node that the record was read from, the source node
          is instructed to remove the record.

    Copyright:
        Copyright (c) 2018 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.Update;

import ocean.meta.types.Qualifiers;
import ocean.core.SmartUnion;
public import swarm.neo.client.NotifierTypes;
public import dhtproto.client.NotifierTypes;

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
    // Notifications that indicate the end of the request:

    /// The request succeeded (either the value was updated or the original
    /// value was left, as specified by the user).
    RequestInfo succeeded;

    /// The specified record does not exist in the DHT so cannot be updated.
    /// You probably want to Put a new record.
    RequestInfo no_record;

    /// The specified record has been updated by another client. Try again.
    RequestInfo conflict;

    /// No DHT node is known to cover the hash of the request. Note that this
    /// may be because the client has just been started and has not received
    /// hash range information from the DHT yet.
    RequestInfo no_node;

    /// An I/O, node, or internal client error occurred while handling the
    /// request.
    RequestInfo error;

    // Notifications about communication with an individual DHT node:

    /// The record was retrieved from the DHT. The updated value to be sent back
    /// should be copied into `received.value_buffer`. (If the buffer is left
    /// empty, the DHT will be told to leave the record as it is.)
    RequestDataUpdateInfo received;

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
}

/*******************************************************************************

    Notification smart union.

*******************************************************************************/

public alias SmartUnion!(NotificationUnion) Notification;

/*******************************************************************************

    Type of notifcation delegate.

*******************************************************************************/

public alias void delegate ( Notification, const(Args) ) Notifier;
