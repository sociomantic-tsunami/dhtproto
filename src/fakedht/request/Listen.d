/*******************************************************************************

    Turtle implementation of DHT `Listen` request

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.request.Listen;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.meta.types.Qualifiers;
import ocean.util.log.Logger;

import swarm.util.Hash;
import Protocol = dhtproto.node.request.Listen;
import fakedht.Storage; // DhtListener

/*******************************************************************************

    Reference to common fakedht logger instance

*******************************************************************************/

private Logger log;

static this ( )
{
    log = Log.lookup("fakedht");
}

/*******************************************************************************

    Listen request protocol

*******************************************************************************/

public scope class Listen : Protocol.Listen, DhtListener
{
    import ocean.core.Verify;
    import fakedht.mixins.RequestConstruction;

    /***************************************************************************

        Indicates whether the request is in the state of its initial wait,
        before any records have been sent to the client

    ***************************************************************************/

    private bool initial_wait = true;

    /***************************************************************************

        Indicates that channel has been deleted and request needs to be
        terminated

    ***************************************************************************/

    private bool channel_deleted;

    /***************************************************************************

        Array of remaining keys in AA to iterate

    ***************************************************************************/

    private istring[] remaining_keys;

    /***************************************************************************

        Remember iterated channel

    ***************************************************************************/

    private Channel channel;

    /***************************************************************************

        Adds this.resources and constructor to initialize it and forward
        arguments to base

    ***************************************************************************/

    mixin RequestConstruction!();

    /***************************************************************************

        Initialize the channel iteration

        Params:
            channel_name = name of channel to be prepared

        Return:
            `true` if it is possible to proceed with request

    ***************************************************************************/

    override protected bool prepareChannel ( cstring channel_name )
    {
        this.channel = global_storage.getCreate(channel_name);
        this.channel.register(this);
        return true;
    }

    /***************************************************************************

        Called upon termination of the request, any cleanup steps can be put
        here.

    ***************************************************************************/

    final override protected void finalizeRequest ( )
    {
        if (this.channel !is null)
            this.channel.unregister(this);
    }


    /***************************************************************************

        Must provide next new DHT record or indicate if it is impossible

        Params:
            channel_name = name of channel to check for new records
            key = slice from HexDigest buffer. Must be filled with record key
                data if it exists. Must not be resized.
            value = must be filled with record value if it exists

        Return:
            'true' if it was possible to get the record, 'false' if more waiting
            is necessary or channel got deleted

    ***************************************************************************/

    override protected bool getNextRecord( cstring channel_name, mstring key,
        out const(void)[] value )
    {
        verify(key.length == HashDigits);

        if (this.remaining_keys.length == 0)
            return false;

        key[] = this.remaining_keys[0];
        value = this.channel.getVerify(key);
        this.remaining_keys = this.remaining_keys[1 .. $].dup;

        log.trace("Listen sends record with key '{}'", key);
        return true;
    }

    /***************************************************************************

        This method gets called to wait for new DHT records and/or report
        any other pending events

        Params:
            finish = indicates if request needs to be ended
            flush =  indicates if socket needs to be flushed

    ***************************************************************************/

    override protected void waitEvents ( out bool finish, out bool flush )
    {
        if ( this.initial_wait )
        {
            // The initial call of this method occurs *before* any records have
            // been sent to the client, hence there's no need to flush the
            // writer.
            this.initial_wait = false;
        }
        else
        {
            // Flush before waiting to ensure that buffered records are sent to
            // the client.
            this.writer.flush();
            this.channel.listenerFlushed();
        }

        // got deleted while waiting for more data
        if (this.channel_deleted)
            finish = true;
        else
            this.event.wait();
    }

    /***************************************************************************

        DhtListener interface method. Called by Storage when new data arrives
        or channel is deleted.

        Params:
            code = trigger event code
            key  = new dht key

    ***************************************************************************/

    public void trigger ( Code code, cstring key )
    {
        with (Code) switch (code)
        {
            case DataReady:
                this.remaining_keys ~= idup(key);
                break;
            case Finish:
                this.channel_deleted = true;
                break;
            default:
               break;
        }

        this.event.trigger();
    }
}
