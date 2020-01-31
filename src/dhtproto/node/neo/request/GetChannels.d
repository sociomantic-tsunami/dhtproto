/*******************************************************************************

    v0 GetChannels request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.GetChannels;

import swarm.neo.node.IRequest;

/// ditto
public abstract class GetChannelsProtocol_v0 : IRequest
{
    import swarm.neo.node.RequestOnConn;
    import swarm.neo.connection.RequestOnConnBase;
    import dhtproto.common.GetChannels;
    import dhtproto.node.neo.request.core.Mixins;
    import ocean.core.Array : copy;
    import ocean.meta.types.Qualifiers;

    /***************************************************************************

        Mixin the initialiser and the connection and resources members.

    ***************************************************************************/

    mixin IRequestHandlerRequestCore!();

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
