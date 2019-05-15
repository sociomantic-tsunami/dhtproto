/*******************************************************************************

    v0 GetChannels request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.GetChannels;

import swarm.neo.node.IRequestHandler;

/// ditto
public abstract class GetChannelsProtocol_v0 : IRequestHandler
{
    import swarm.neo.node.RequestOnConn;
    import swarm.neo.connection.RequestOnConnBase;
    import dhtproto.common.GetChannels;
    import dhtproto.node.neo.request.core.Mixins;
    import ocean.core.Array : copy;
    import ocean.transition;

    /***************************************************************************

        Mixin the initialiser and the connection and resources members.

    ***************************************************************************/

    mixin IRequestHandlerRequestCore!();

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
        // Nothing more to parse from the payload.
    }

    /***************************************************************************

        Called by the connection handler after the supported code has been sent
        back to the client.

    ***************************************************************************/

    public void postSupportedCodeSent ( )
    {
        auto channel_buf = this.resources.getVoidBuffer();

        foreach ( channel; this )
        {
            // Copy the channel name in case it changes during sending.
            (*channel_buf).copy(channel);

            this.connection.event_dispatcher.send(
                ( RequestOnConnBase.EventDispatcher.Payload payload )
                {
                    payload.addCopy(MessageType.ChannelName);
                    payload.addArray(*channel_buf);
                }
            );
        }

        // Send finished code
        this.connection.event_dispatcher.send(
            ( RequestOnConnBase.EventDispatcher.Payload payload )
            {
                payload.addCopy(MessageType.Finished);
            }
        );
    }

    /***************************************************************************

        opApply iteration over the names of the channels in storage.

    ***************************************************************************/

    protected abstract int opApply ( scope int delegate ( ref cstring ) dg );
}
