/*******************************************************************************

    Protocol definition of the DHT Update request.

    Copyright:
        Copyright (c) 2018 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.common.Update;

/*******************************************************************************

    Message code enum

*******************************************************************************/

public enum MessageType : ubyte
{
    /// Invalid, default value
    None,

    // Sent from the client to the node:

    /// Client requesting record value from a node
    GetRecord,
    /// Client requesting to update record value on a node
    UpdateRecord,
    /// Client informing node that record was updated on another node and can be
    /// removed
    RemoveRecord,
    /// Client informing node that record should be left as it is
    LeaveRecord,

    // Sent from the node to the client:

    /// Record value sent from node
    RecordValue,
    /// Record value updated / left / removed, per client's request
    Ok,
    /// Record does not exist in node
    NoRecord,
    /// Record has been updated by another client. The request may be retried
    UpdateConflict,
    /// Node is not responsible for record key
    WrongNode,
    /// Internal node error occurred
    Error
}
