/*******************************************************************************

    Custom exception types which can be thrown inside a dht client.

    Copyright:
        Copyright (c) 2011-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.DhtClientExceptions;



/*******************************************************************************

    Imports

*******************************************************************************/

import swarm.client.ClientExceptions;



/*******************************************************************************

    Exception passed to user notifier when a request is assigned to the client
    before the node's API version is known (i.e. before the handshake has been
    performed) or when the API is known but does not match the client's.

*******************************************************************************/

public class VersionException : ClientException
{
    public this ( )
    {
        super("Node API version not queried or mismatched " ~
            "-- handshake probably not completed");
    }
}


/*******************************************************************************

    Exception passed to user notifier when the handshake reports multiple nodes
    which cover the same hash range.

*******************************************************************************/

public class NodeOverlapException : ClientException
{
    public this ( )
    {
        super("Multiple nodes responsible for key");
    }
}


/*******************************************************************************

    Exception passed to user notifier when the filter string passed by the user
    (to a bulk request which supports filtering) is empty.

*******************************************************************************/

public class NullFilterException : ClientException
{
    public this ( )
    {
        super("Filter not set");
    }
}


/*******************************************************************************

    Exception thrown when attempting to modify the node registry (via the
    addNode() or addNodes() methods of DhtClient) when it has already been
    locked. Locking occurs after the handshake is executed.

*******************************************************************************/

public class RegistryLockedException : ClientException
{
    public this ( )
    {
        super("Node registry is locked");
    }
}


