/*******************************************************************************

    Protocol definition of the DHT Get request.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.common.Get;

/*******************************************************************************

    Message type enum. Sent from the node to the client.

*******************************************************************************/

public enum MessageType : ubyte
{
    /// Invalid, default value
    None,

    /// Record does not exist
    NoRecord,

    /// Value read from DHT
    Got,

    /// Node is not responsible for record key
    WrongNode,

    /// Internal node error occurred
    Error
}
