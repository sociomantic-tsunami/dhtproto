/*******************************************************************************

    Protocol base for DHT `Listen` request

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.Listen;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhtproto.node.request.model.SingleChannel;

/*******************************************************************************

    Listen request protocol

*******************************************************************************/

public abstract scope class Listen : SingleChannel
{
    import dhtproto.node.request.model.DhtCommand;

    import dhtproto.client.legacy.DhtConst;
    import swarm.common.request.helper.DisconnectDetector;
    import Hash = swarm.util.Hash;

    /***************************************************************************

        Constructor

        Params:
            reader = FiberSelectReader instance to use for read requests
            writer = FiberSelectWriter instance to use for write requests
            resources = object providing resource getters

    ***************************************************************************/

    public this ( FiberSelectReader reader, FiberSelectWriter writer,
        DhtCommand.Resources resources )
    {
        super(DhtConst.Command.E.Listen, reader, writer, resources);
    }

    /***************************************************************************

        Keeps sending new records in dht channel to client until channel
        gets removed or client closes connection
    
        Params:
            channel_name = channel name for request that was read and validated
                earlier

    ***************************************************************************/

    final override protected void handleChannelRequest( cstring channel_name )
    {
        this.writer.write(DhtConst.Status.E.Ok);

        scope disconnect_detector = new DisconnectDetector(
            this.writer.fileHandle, &this.onDisconnect);

        bool flush, finish;

        // Note: the Finish code is only received when the storage channel being
        // listened to is recycled.
        while (!finish)
        {
            // Listen for disconnections instead of "write" events while we are
            // waiting. When the wait is over, is either because we have more
            // records to send or we need to flush, both operations needing to
            // activate the "write" events again (or we disconnected, in which case
            // the cleanup also assumes the "write" event was active).
            this.writer.fiber.unregister();
            this.reader.fiber.epoll.register(disconnect_detector);
            this.waitEvents(finish, flush);
            this.reader.fiber.epoll.unregister(disconnect_detector);

            if (disconnect_detector.disconnected)
                return;
        
            this.writer.fiber.register(this.writer);

            Hash.HexDigest key;
            Const!(void)[] value;

            while (this.getNextRecord(channel_name, key[], value))
            {
                this.writer.writeArray(key);
                this.writer.writeArray(value);
            }

            if (flush)
                this.writer.flush();
        }

        // Write empty key and value, informing the client that the request has
        // finished
        this.writer.writeArray("");
        this.writer.writeArray("");
    }

    /***************************************************************************

        Must provide next new DHT record or indicate if it is impossible

        Params:
            channel_name = name of channel to check for new records
            key = slice from HexDigest buffer. Must be filled with record key
                data if it exists. Must not be resized.
            value = must be assigned with record value slice if it exists

        Return:
            'true' if it was possible to get the record, 'false' if more waiting
            is necessary or channel got deleted

    ***************************************************************************/

    abstract protected bool getNextRecord( cstring channel_name, mstring key,
        out Const!(void)[] value );

    /***************************************************************************

        This method gets called to wait for new DHT records and/or report
        any other pending events

        Params:
            finish = indicates if request needs to be ended
            flush =  indicates if socket needs to be flushed

    ***************************************************************************/

    abstract protected void waitEvents ( out bool finish, out bool flush );

    /***************************************************************************

        Action to trigger when a disconnection is detected. No-op by
        default.

    ***************************************************************************/

    protected void onDisconnect ( ) { }
}
