/*******************************************************************************

    Protocol definition of the DHT Remove request.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.common.Remove;

/*******************************************************************************

    Status code enum. Sent from the node to the client.

*******************************************************************************/

public enum MessageType : ubyte
{
    /// Invalid, default value
    None,

    /// Record does not exist
    NoRecord,

    /// Value removed from DHT
    Removed,

    /// Node is not responsible for record key
    WrongNode,

    /// Internal node error occurred
    Error
}
