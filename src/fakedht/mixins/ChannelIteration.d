/*******************************************************************************

    Mixin for shared iteration code

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.mixins.ChannelIteration;

import ocean.transition;

/*******************************************************************************

    Indicates if it is necessary to inject version for key-only iteration
    or both keys + values

*******************************************************************************/

enum IterationKind
{
    Key,
    KeyValue
}

/*******************************************************************************

    Common code shared by all requests that implement protocol based on
    dhtproto.node.request.model.CompressedBatch 

    Template Params:
        kind = indicates which version of getNext to generate
        predicate = optional predicate function to filter away some records.
            Defaults to predicate that allows everything.

*******************************************************************************/

public template ChannelIteration ( IterationKind kind,
    alias predicate = alwaysTrue )
{
    import fakedht.Storage;
    import ocean.transition;
    import ocean.core.Tuple;
    import ocean.core.TypeConvert;

    /***************************************************************************

        Convenience alias for argument set getNext should expect

    ***************************************************************************/

    static if (kind == IterationKind.Key)
    {
        private alias Tuple!(mstring) ARGS;
    }
    else
    {
        private alias Tuple!(mstring, mstring) ARGS;
    }

    /***************************************************************************

        Array of remaining keys in AA to iterate

    ***************************************************************************/

    private istring[] remaining_keys;

    /***************************************************************************

        Remember iterated channel

    ***************************************************************************/

    private Channel channel;

    /***************************************************************************

        Initialize the channel iterator

        Params:
            channel_name = name of channel to be prepared

        Return:
            `true` if it is possible to proceed with request

    ***************************************************************************/

    override protected bool prepareChannel ( cstring channel_name )
    {
        this.channel = global_storage.get(channel_name);
        if (this.channel !is null)
            this.remaining_keys = this.channel.getKeys();
        else
            this.remaining_keys = null;

        // add dummy entry at front so that it can be moved forward
        // in the beginning of `getNext`
        this.remaining_keys = "dummy"[] ~ this.remaining_keys;
        return true;
    }

    /***************************************************************************
        
        Iterates records for the protocol

        Params:
            args = either key or key + value, depending on request type

        Returns:
            `true` if there was data, `false` if request is complete

    ***************************************************************************/

    override protected bool getNext (out ARGS args)
    {
        // loops either until match is found or last key processed
        while (true)
        {
            // The first time around the loop, the dummy key added by
            // prepareChannel() will be discarded
            this.remaining_keys = this.remaining_keys[1 .. $];

            // no more data
            if (this.remaining_keys.length == 0) 
                return false;

            static if (kind == IterationKind.Key)
            {
                args[0] = this.remaining_keys[0].dup;
            }
            else
            {
                args[0] = this.remaining_keys[0].dup;
                args[1] = castFrom!(Const!(void)[]).to!(cstring)(
                    this.channel.get(this.remaining_keys[0])).dup;
            }

            if (predicate(args))
                return true;
        }
    }
}

/*******************************************************************************

    Default predicate which allows all records to be sent to the client.

    Params:
        args = any arguments

    Returns:
        true

*******************************************************************************/

public bool alwaysTrue ( T... ) ( T args )
{
    return true;
}
