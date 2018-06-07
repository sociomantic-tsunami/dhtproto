/*******************************************************************************

    Get request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.Get;

import swarm.neo.node.IRequestHandler;

/*******************************************************************************

    v0 Get request protocol.

*******************************************************************************/

public abstract class GetProtocol_v0 : IRequestHandler
{
    import swarm.neo.node.RequestOnConn;
    import dhtproto.common.Get;
    import dhtproto.node.neo.request.core.Mixins;

    import ocean.transition;
    import ocean.core.Verify;
    import ocean.core.array.Mutation : copy;

    /***************************************************************************

        Mixin the initialiser and the connection and resources members.

    ***************************************************************************/

    mixin IRequestHandlerRequestCore!();

    /// Name of channel to read from.
    private void[]* channel;

    /// Key to be read.
    private hash_t key;

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

        this.channel = this.resources.getVoidBuffer();
        (*this.channel).copy(ed.message_parser.getArray!(char)(init_payload));
        enableStomping(*this.channel);
        this.key = *ed.message_parser.getValue!(hash_t)(init_payload);
    }

    /***************************************************************************

        Called by the connection handler after the supported code has been sent
        back to the client.

    ***************************************************************************/

    public void postSupportedCodeSent ( )
    {
        auto ed = this.connection.event_dispatcher();

        void sendResponse ( MessageType status_code,
            void delegate ( ed.Payload ) extra = null )
        {
            ed.send(
                ( ed.Payload payload )
                {
                    payload.add(status_code);
                }
            );

            // TODO: this could be sent in the same message as the status code,
            // above. (Client would need to be adaptated.)
            if ( extra !is null )
                ed.send(extra);
        }

        // Check record key and read from channel, if ok.
        if ( this.responsibleForKey(this.key) )
        {
            bool sent;
            auto ok = this.get(cast(char[])*this.channel, this.key,
                ( Const!(void)[] value )
                {
                    verify(value !is null);
                    verify(value.length > 0);

                    sendResponse(MessageType.Got,
                        ( ed.Payload payload )
                        {
                            payload.addArray(value);
                        }
                    );

                    sent = true;
                }
            );

            if ( !sent )
                sendResponse(ok ? MessageType.NoRecord
                                : MessageType.Error);
        }
        else
            sendResponse(MessageType.WrongNode);

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

        Gets a single record from the storage engine.

        Params:
            channel = channel to read from
            key = key of record to read
            dg = called with the value of the record, if it exists

        Returns:
            true if the operation succeeded (the record was fetched or did not
            exist); false if an error occurred

    ***************************************************************************/

    abstract protected bool get ( cstring channel, hash_t key,
        void delegate ( Const!(void)[] value ) dg );
}
