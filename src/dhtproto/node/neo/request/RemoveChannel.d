/*******************************************************************************

    v0 RemoveChannel request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.RemoveChannel;

import ocean.core.VersionCheck;
import ocean.util.log.Logger;
import swarm.neo.node.IRequest;

/// ditto
public abstract scope class RemoveChannelProtocol_v0 : IRequest
{
    import swarm.neo.node.RequestOnConn;
    import dhtproto.common.RemoveChannel;
    import dhtproto.node.neo.request.core.Mixins;

    import ocean.transition;

    /// Mixin the initialiser and the connection and resources members.
    mixin IRequestHandlerRequestCore!();

    /// Response to client.
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
        Const!(void)[] init_payload )
    {
        // Dummy implementation to satisfy interface definition
    }

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
        auto channel = this.connection.event_dispatcher.message_parser.
            getArray!(char)(init_payload);

        if ( !this.clientPermitted(this.connection.getClientName()) )
        {
            this.response = MessageType.NotPermitted;
            return;
        }

        this.response = this.removeChannel(channel)
            ? MessageType.ChannelRemoved : MessageType.Error;
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
                payload.add(this.response);
            }
        );

        static if (!hasFeaturesFrom!("swarm", 4, 7))
            ed.flush();
    }

    /***************************************************************************

        Checks whether the specified client is permitted to remove channels.

        Params:
            client_name = name of client requesting channel removal

        Returns:
            true if the client is permitted to remove channels

    ***************************************************************************/

    abstract protected bool clientPermitted ( cstring client_name );

    /***************************************************************************

        Removes the specified channel.

        Params:
            channel_name = channel to remove

        Returns:
            true if the operation succeeded (the channel was removed or did not
            exist); false if an error occurred

    ***************************************************************************/

    abstract protected bool removeChannel ( cstring channel_name );
}
