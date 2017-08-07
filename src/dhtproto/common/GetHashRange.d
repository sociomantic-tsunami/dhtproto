/*******************************************************************************

    Protocol definition of the DHT GetHashRange request.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.common.GetHashRange;

import swarm.neo.request.Command;

/*******************************************************************************

    Status code enum. Sent from the node to the client.

*******************************************************************************/

public enum RequestStatusCode : StatusCode
{
    /// Invalid, default value
    None,

    /// GetHashRange started
    Started,

    /// Internal node error occurred
    Error
}

/*******************************************************************************

    Message type enum. Each message sent between the node and the client as part
    of a GetHashRange request is prepended by a type indicator.

*******************************************************************************/

public enum MessageType : ubyte
{
    /// Invalid, default value
    None,

    /// The node handling the GetHashRange request has been informed about the
    /// existence of another DHT node, which it forwards in this message. The
    /// other node may be previously unknown to the client (in which case, an
    /// entry is added to the node hash range registry) or may be already known
    /// to the client (in which case, its entry in the registry is updated).
    NewNode,

    /// The node handling the GetHashRange request has changed its hash range.
    /// An entry is added to the node hash range registry.
    ChangeHashRange
}
