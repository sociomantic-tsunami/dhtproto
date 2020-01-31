/*******************************************************************************

    Client DHT GetChannels request definitions / handler.

    The GetChannels request communicates with all DHT nodes to fetch the names
    of all channels in the DHT. If a connection error occurs, the request will
    be restarted once the connection has been re-established.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.GetChannels;

import ocean.meta.types.Qualifiers;
import ocean.core.SmartUnion;
public import swarm.neo.client.NotifierTypes;

/*******************************************************************************

    Request-specific arguments provided by the user and passed to the notifier.

*******************************************************************************/

public struct Args
{
    // Nothing.
}

/*******************************************************************************

    Union of possible notifications.

    The following notifications are considered fatal (i.e. the request will
    almost certainly get the same error if retried):
    * node_error
    * unsupported

*******************************************************************************/

private union NotificationUnion
{
    /// A channel name has been received from the DHT.
    RequestDataInfo received;

    /// The connection to a node has disconnected; the request will
    /// automatically restart after reconnection.
    RequestNodeExceptionInfo node_disconnected;

    /// A node returned a non-OK status code. The request cannot be handled by
    /// this node.
    RequestNodeInfo node_error;

    /// The request was tried on a node and failed because it is unsupported.
    /// The request cannot be handled by this node.
    RequestNodeUnsupportedInfo unsupported;

    /// All known nodes have either finished the request or are not currently
    /// connected. The request is now finished.
    RequestInfo finished;
}

/*******************************************************************************

    Notification smart union.

*******************************************************************************/

public alias SmartUnion!(NotificationUnion) Notification;

/*******************************************************************************

    Type of notification delegate.

*******************************************************************************/

public alias void delegate ( Notification, const(Args) ) Notifier;
