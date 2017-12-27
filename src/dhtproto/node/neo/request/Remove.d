/*******************************************************************************

    Remove request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.Remove;

import swarm.neo.node.IRequestHandler;

/*******************************************************************************

    v0 Remove request protocol.

*******************************************************************************/

public abstract class RemoveProtocol_v0 : IRequestHandler
{
    import swarm.neo.node.RequestOnConn;
    import dhtproto.common.Remove;
    import dhtproto.node.neo.request.core.Mixins;

    import ocean.transition;

    /// Mixin the initialiser and the connection and resources members.
    mixin IRequestHandlerRequestCore!();

    /// Response status code to send to client.
    private MessageType response;

    /***************************************************************************

        Called by the connection handler immediately after the request code and
        version have been parsed from a message received over the connection.
        Allows the request handler to process the remainder of the incoming
        message, before the connection handler sends the supported code back to
        the client.

        Note: the initial payload is a slice of the connection's read buffer.
        This means that when the request-on-conn fiber suspends, the contents of
        the buffer (hence the slice) may change. It is thus *absolutely
        essential* that this method does not suspend the fiber. (This precludes
        all I/O operations on the connection.)

        Params:
            init_payload = initial message payload read from the connection

    ***************************************************************************/

    public void preSupportedCodeSent ( Const!(void)[] init_payload )
    {
        auto parser = this.connection.event_dispatcher.message_parser();

        cstring channel;
        hash_t key;
        parser.parseBody(init_payload, channel, key);

        // Check record key and remove from channel, if ok.
        if ( this.responsibleForKey(key) )
        {
            bool removed;
            if ( this.remove(channel, key, removed) )
                this.response = removed
                    ? MessageType.Removed : MessageType.NoRecord;
            else
                this.response = MessageType.Error;
        }
        else
            this.response = MessageType.WrongNode;
    }

    /***************************************************************************

        Called by the connection handler after the supported code has been sent
        back to the client.

    ***************************************************************************/

    public void postSupportedCodeSent ( )
    {
        auto ed = this.connection.event_dispatcher();

        // Send response message
        ed.send(
            ( ed.Payload payload )
            {
                payload.add(this.response);
            }
        );
        ed.flush();
    }

    /***************************************************************************

        Checks whether the node is responsible for the specified key.

        Params:
            key = key of record to write

        Returns:
            true if the node is responsible for the key

    ***************************************************************************/

    abstract protected bool responsibleForKey ( hash_t key );

    /***************************************************************************

        Removes a single record from the storage engine.

        Params:
            channel = channel to remove from
            key = key of record to remove
            existed = out value, set to true if the record was present and
                removed or false if the record was not present

        Returns:
            true if the operation succeeded (the record was removed or did not
            exist); false if an error occurred

    ***************************************************************************/

    abstract protected bool remove ( cstring channel, hash_t key,
        out bool existed );
}
