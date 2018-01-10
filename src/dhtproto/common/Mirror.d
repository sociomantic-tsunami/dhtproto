/*******************************************************************************

    Protocol definition of the DHT Mirror request.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.common.Mirror;

import swarm.neo.request.Command;

/*******************************************************************************

    Message type enum. Each message sent between the client and the node as part
    of a Mirror request is prepended by a type indicator.

*******************************************************************************/

public enum MessageType : ubyte
{
    None,       // Invalid, default value

    // Message types sent from the client to the node:
    Suspend,    // Sent when the client wants the node to stop sending records
    Resume,     // Sent when the client wants the node to resume sending records
    Stop,       // Sent when the client wants the node to cleanly end the request

    // Message types sent between the client and the node (in either direction):
    Ack,            // Sent by the node to acknowledge a state change message;
                    // sent by the client to acknowledge the request finishing

    // Message types sent from the node to the client:
    Started,        // Request handling beginning
    Error,          // Internal node error occurred; request not being handled
    RecordChanged,  // Sent by the node when it sends a record value
    RecordDeleted,  // Sent by the node when it sends the key of a deleted record
    RecordRefreshBatch, // Sent by the node when it sends a batch of refreshed
                        // records
    ChannelRemoved, // Sent when the channel being consumed is removed
    UpdateOverflow  // Sent when the queue of updates overflows
}
