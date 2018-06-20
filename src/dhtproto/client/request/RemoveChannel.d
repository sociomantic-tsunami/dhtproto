/*******************************************************************************

    Client DHT RemoveChannel request definitions / handler.

    The RemoveChannel request instructs all DHT nodes to remove the named
    channel. As removing a channel is a major operation, the node only allows
    clients named "admin" (naturally, with the appropriate authentication) to
    perform the request.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.request.RemoveChannel;

import ocean.transition;
import ocean.core.SmartUnion;
public import swarm.neo.client.NotifierTypes;

/*******************************************************************************

    Request-specific arguments provided by the user and passed to the notifier.

*******************************************************************************/

public struct Args
{
    mstring channel;
}

/*******************************************************************************

    Union of possible notifications.

*******************************************************************************/

private union NotificationUnion
{
    /// All known nodes have either handled the request or are not currently
    /// connected. The request is now finished.
    RequestInfo finished;

    /// One or more nodes refused to handle the request because the client does
    /// not have admin permissions. Get permission before retrying.
    RequestInfo not_permitted;

    /// The connection to a node has disconnected; the request will
    /// automatically continue on this node after reconnection.
    RequestNodeExceptionInfo node_disconnected;

    /// A node returned a non-OK status code. The request cannot be handled by
    /// this node.
    RequestNodeInfo node_error;

    /// The request was tried on a node and failed because it is unsupported.
    /// The request cannot be handled by this node.
    RequestNodeUnsupportedInfo unsupported;
}

/*******************************************************************************

    Notification smart union.

*******************************************************************************/

public alias SmartUnion!(NotificationUnion) Notification;

/*******************************************************************************

    Type of notification delegate.

*******************************************************************************/

public alias void delegate ( Notification, Args ) Notifier;
