/*******************************************************************************

    v0 GetChannels request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.GetChannels;

/// ditto
public abstract scope class GetChannelsProtocol_v0
{
    import swarm.neo.node.RequestOnConn;
    import swarm.neo.connection.RequestOnConnBase;
    import dhtproto.common.GetChannels;
    import dhtproto.node.neo.request.core.Mixins;
    import ocean.core.Array : copy;
    import ocean.transition;

    /// Mixin the constructor and resources member.
    mixin RequestCore!();

    /// Connection to the client.
    private RequestOnConn connection;

    /***************************************************************************

        Request handler. Responds to the client with a status code and sends the
        list of channels.

        Params:
            connection = connection to client
            msg_payload = initial message read from client to begin the request
                (the request code and version are assumed to be extracted)

    ***************************************************************************/

    final public void handle ( RequestOnConn connection,
        Const!(void)[] msg_payload )
    {
        this.connection = connection;

        // Send status code
        this.connection.event_dispatcher.send(
            ( RequestOnConnBase.EventDispatcher.Payload payload )
            {
                payload.addConstant(RequestStatusCode.Started);
            }
        );

        auto channel_buf = this.resources.getVoidBuffer();

        foreach ( channel; this )
        {
            // Copy the channel name in case it changes during sending.
            (*channel_buf).copy(channel);

            this.connection.event_dispatcher.send(
                ( RequestOnConnBase.EventDispatcher.Payload payload )
                {
                    payload.addConstant(MessageType.ChannelName);
                    payload.addArray(*channel_buf);
                }
            );
        }

        // Send finished code
        this.connection.event_dispatcher.send(
            ( RequestOnConnBase.EventDispatcher.Payload payload )
            {
                payload.addConstant(MessageType.Finished);
            }
        );
    }

    /***************************************************************************

        opApply iteration over the names of the channels in storage.

    ***************************************************************************/

    protected abstract int opApply ( int delegate ( ref cstring ) dg );
}
