/*******************************************************************************

    Protocol base for DHT `Put` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.Put;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import dhtproto.node.request.model.SingleKey;

/*******************************************************************************

    Request protocol

*******************************************************************************/

public abstract scope class Put : SingleKey
{
    import dhtproto.node.request.model.DhtCommand;

    import dhtproto.client.legacy.DhtConst;

    /***************************************************************************

        Flag that indicates if it was actually possible to read the record
        from the client. It will only be 'false' if record was larger than size
        limit.

    ***************************************************************************/

    private bool record_read;

    /***************************************************************************

        Used to read the record value into.

    ***************************************************************************/

    private mstring* value_buffer;

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
        super(DhtConst.Command.E.Put, reader, writer, resources);
        this.value_buffer = this.resources.getValueBuffer();
    }

    /***************************************************************************

        Read the record value from the client, unless it exceeds the
        per-record size limit (see recordSizeLimit

    ***************************************************************************/

    override protected void readKeyRequestData ( )
    {
        this.record_read = this.reader.readArrayLimit(
            *this.value_buffer, this.recordSizeLimit()
        );
    }

    /***************************************************************************

        Returns:
            the maximum size (in bytes) allowed for a record to be added to the
            storage engine

    ***************************************************************************/

    protected size_t recordSizeLimit ( )
    {
        return DhtConst.RecordSizeLimit;
    }

    /***************************************************************************

        Stores incoming record

        Params:
            channel_name = channel name for request that was read and validated
                earlier
            key = any string that can act as DHT key

    ***************************************************************************/

    final override protected void handleSingleKeyRequest ( cstring channel_name,
        cstring key )
    {
        auto value = *this.value_buffer;

        if (!this.record_read)
        {
            this.writer.write(DhtConst.Status.E.ValueTooBig);
            return;
        }

        if (!value.length)
        {
            this.writer.write(DhtConst.Status.E.EmptyValue);
            return;
        }

        if (!this.isSizeAllowed(value.length))
        {
            this.writer.write(DhtConst.Status.E.OutOfMemory);
            return;
        }

        if (!this.putRecord(channel_name, key, value))
        {
            this.writer.write(DhtConst.Status.E.Error);
            return;
        }
        else
        {
            this.writer.write(DhtConst.Status.E.Ok);
            return;
        }
    }

    /***************************************************************************

        Verifies that this node is allowed to store records of given size

        Params:
            size = size to check

        Returns:
            'true' if size is allowed

    ***************************************************************************/

    abstract protected bool isSizeAllowed ( size_t size );

    /***************************************************************************

        Tries storing record in DHT and reports success status

        Params:
            channel = channel to write record to
            key = record key
            value = record value

        Returns:
            'true' if storing was successful

    ***************************************************************************/

    abstract protected bool putRecord ( cstring channel, cstring key,
        in void[] value );
}
