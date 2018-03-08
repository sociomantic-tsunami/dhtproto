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

    Note that this request enforces a size limit on record values (see
    MaxRecordSize constant, below).

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
import swarm.util.RecordBatcher;

/// Maximum allowed size of record values. The maximum record value size depends
/// on the size of the batch used by GetAll requests. It must not be possible to
/// store a record in the DHT that cannot be returned by a GetAll request.
// TODO: ideally, the GetAll batch size should be defined in terms of the
// maximum record size, not the other way around. However, support for easily
// calculating the required size of a record batch based on the size of a record
// that can fit in it is lacking.
// See https://github.com/sociomantic-tsunami/swarm/issues/142
public const MaxRecordSize =
    RecordBatcher.DefaultMaxBatchSize - hash_t.sizeof - (size_t.sizeof * 2);

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

    /// The length of the provided record value exceeds the MaxRecordSize
    /// constant (see above).
    RequestInfo value_too_big;

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

public alias void delegate ( Notification, Const!(Args) ) Notifier;
