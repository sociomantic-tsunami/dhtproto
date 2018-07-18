/*******************************************************************************

    Put request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.Put;

import ocean.core.VersionCheck;
import swarm.neo.node.IRequestHandler;

/*******************************************************************************

    v0 Put request protocol.

*******************************************************************************/

public abstract class PutProtocol_v0 : IRequestHandler
{
    import swarm.neo.node.RequestOnConn;
    import dhtproto.common.Put;
    import dhtproto.node.neo.request.core.Mixins;

    import ocean.transition;

    /***************************************************************************

        Mixin the initialiser and the connection and resources members.

    ***************************************************************************/

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
    }

    /***************************************************************************

        Called by the connection handler after the supported code has been sent
        back to the client.

    ***************************************************************************/

    public void postSupportedCodeSent ( )
    {
        auto ed = this.connection.event_dispatcher();

        // Send status code
        ed.send(
            ( ed.Payload payload )
            {
                payload.add(response);
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
