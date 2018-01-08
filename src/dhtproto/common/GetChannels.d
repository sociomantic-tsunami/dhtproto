/*******************************************************************************

    Protocol definition of the DHT GetChannels request.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.common.GetChannels;

import swarm.neo.request.Command;

/*******************************************************************************

    Message type enum. Each message sent between the client and the node as part
    of a GetChannels request is prepended by a type indicator.

*******************************************************************************/

public enum MessageType : ubyte
{
    None,       // Invalid, default value

    // Message types sent from the node to the client:
    Error,          // Internal node error
    ChannelName,    // Sent by the node when it sends a channel name
    Finished        // Send by the node when the request is finished
}
