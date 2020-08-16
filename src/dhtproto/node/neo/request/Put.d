/*******************************************************************************

    Put request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.Put;

import ocean.core.VersionCheck;
import swarm.neo.node.IRequest;

/*******************************************************************************

    v0 Put request protocol.

*******************************************************************************/

public abstract class PutProtocol_v0 : IRequest
{
    import swarm.neo.node.RequestOnConn;
    import dhtproto.common.Put;
    import dhtproto.node.neo.request.core.Mixins;

    import ocean.meta.types.Qualifiers;

    /***************************************************************************

        Mixin the initialiser and the connection and resources members.

    ***************************************************************************/

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

        auto ed = this.connection.event_dispatcher();

        auto channel = ed.message_parser.getArray!(char)(init_payload);
        auto key = *ed.message_parser.getValue!(hash_t)(init_payload);
        auto value = ed.message_parser.getArray!(void)(init_payload);

        // Check record key and write to channel, if ok.
        if ( this.responsibleForKey(key) )
        {
            this.response = this.put(channel, key, value)
                ? MessageType.Put : MessageType.Error;
        }
        else
            this.response = MessageType.WrongNode;

        // Send status code
        ed.send(
            ( ed.Payload payload )
            {
                payload.add(response);
            }
        );
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

        Writes a single record to the storage engine.

        Params:
            channel = channel to write to
            key = key of record to write
            value = record value to write

        Returns:
            true if the record was written; false if an error occurred

    ***************************************************************************/

    abstract protected bool put ( cstring channel, hash_t key, in void[] value );
}
