/*******************************************************************************

    Remove request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.Remove;

import ocean.core.VersionCheck;
import swarm.neo.node.IRequest;

/*******************************************************************************

    v0 Remove request protocol.

*******************************************************************************/

public abstract class RemoveProtocol_v0 : IRequest
{
    import swarm.neo.node.RequestOnConn;
    import dhtproto.common.Remove;
    import dhtproto.node.neo.request.core.Mixins;

    import ocean.meta.types.Qualifiers;

    /// Mixin the initialiser and the connection and resources members.
    mixin IRequestHandlerRequestCore!();

    /// Response status code to send to client.
    private MessageType response;

    /***************************************************************************

        Called by the connection handler after the request code and version have
        been parsed from a message received over the connection, and the
        request-supported code sent in response.

        Note: the initial payload passed to this method is a slice of a buffer
        owned by the RequestOnConn. It is thus safe to assume that the contents
        of the buffer will not change over the lifetime of the request.

        Params:
            connection = request-on-conn in which the request handler is called
            resources = request resources acquirer
            init_payload = initial message payload read from the connection

    ***************************************************************************/

    public void handle ( RequestOnConn connection, Object resources,
        const(void)[] init_payload )
    {
        this.initialise(connection, resources);

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

        auto ed = this.connection.event_dispatcher();

        // Send response message
        ed.send(
            ( ed.Payload payload )
            {
                payload.add(this.response);
            }
        );

        static if (!hasFeaturesFrom!("swarm", 4, 7))
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
