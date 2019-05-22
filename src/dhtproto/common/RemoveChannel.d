/*******************************************************************************

    Protocol definition of the DHT RemoveChannel request.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.common.RemoveChannel;

/*******************************************************************************

    Status code enum. Sent from the node to the client.

*******************************************************************************/

public enum MessageType : ubyte
{
    /// Invalid, default value
    None,

    /// RemoveChannel succeeded
    ChannelRemoved,

    /// Channel cannot be removed as the client does not have admin permissions
    NotPermitted,

    /// Internal node error occurred
    Error
}
