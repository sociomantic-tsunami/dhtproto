/*******************************************************************************

    Abstract base class for dht node request on a single channel with single
    key argument.

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.model.SingleKey;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhtproto.node.request.model.SingleChannel;

/*******************************************************************************

    Common base for single channel request protocols

    It extends SingleChannel with reading additional argument from the
    client and checks that key is in allowed range.

*******************************************************************************/

public abstract scope class SingleKey : SingleChannel
{
    import dhtproto.node.request.model.DhtCommand;

    import dhtproto.client.legacy.DhtConst;
    import swarm.Const : validateChannelName;

    /***************************************************************************

        Pointer to the key buffer, provided to the constructor. Used to read
        the record key into.

    ***************************************************************************/

    private mstring* key_buffer;

    /***************************************************************************

        Constructor

        Params:
            cmd = command code
            reader = FiberSelectReader instance to use for read requests
            writer = FiberSelectWriter instance to use for write requests
            resources = object providing resource getters

    ***************************************************************************/

    public this ( DhtConst.Command.E cmd, FiberSelectReader reader,
        FiberSelectWriter writer, DhtCommand.Resources resources )
    {
        super(cmd, reader, writer, resources);
        this.key_buffer = this.resources.getKeyBuffer();
    }

    /***************************************************************************

        Read key argument

    ***************************************************************************/

    final override protected void readChannelRequestData ( )
    {
        if (!this.reader.readArrayLimit(*this.key_buffer, MaximumRecordSize))
        {
            throw this.inputException.set(
                    "Error while reading the request key: too large");
        }
        this.readKeyRequestData();
    }

    /***************************************************************************

        If protocol for derivative request needs any parameters other than
        key, channel name and request code, this method must be overridden to
        read and store those.

    ***************************************************************************/

    protected void readKeyRequestData ( ) { }

    /***************************************************************************

        Forwards handling to method aware of additional key argument

        Params:
            channel_name = channel name for request that was read and validated
                earlier

    ***************************************************************************/

    final override protected void handleChannelRequest ( cstring channel_name )
    {
        auto key = *this.key_buffer;

        if (!this.isAllowed(key))
        {
            this.writer.write(DhtConst.Status.E.WrongNode);
            return;
        }

        this.handleSingleKeyRequest(channel_name, key);
    }

    /***************************************************************************

        Verifies that this node is responsible of handling specified record key

        Params:
            key = key to check

        Returns:
            'true' if key is allowed / accepted

    ***************************************************************************/

    abstract protected bool isAllowed ( cstring key );

    /***************************************************************************

       Params:
            channel_name = channel name for request that was read and validated
                earlier
            key = any string that can act as DHT key

    ***************************************************************************/

    abstract protected void handleSingleKeyRequest( cstring channel_name,
        cstring key );
}
