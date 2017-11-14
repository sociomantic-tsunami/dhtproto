/*******************************************************************************

    Protocol definition of the DHT Exists request.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.common.Exists;

/*******************************************************************************

    Status code enum. Sent from the node to the client.

*******************************************************************************/

public enum MessageType : ubyte
{
    /// Invalid, default value
    None,

    /// Record exists
    RecordExists,

    /// Record does not exist
    NoRecord,

    /// Node is not responsible for record key
    WrongNode,

    /// Internal node error occurred
    Error
}
