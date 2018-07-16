/*******************************************************************************

    Abstract base class that acts as a root for all dht protocol classes

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.request.model.DhtCommand;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import swarm.node.protocol.Command;

/*******************************************************************************
    
    DHT command base class

*******************************************************************************/

public abstract scope class DhtCommand : Command
{
    import dhtproto.node.request.params.RedistributeNode;

    import ocean.core.Exception;
    import swarm.util.RecordBatcher;
    import dhtproto.client.legacy.DhtConst;

    /***************************************************************************

        Absolute maximum record size. Used for sanitizing the data input.
        All records larger than this will be discarded.

    **************************************************************************/

    protected const MaximumRecordSize = 10 * 1024 * 1024;

    /***************************************************************************

        Exception instance to throw in case of the input validation error.

    ***************************************************************************/

    public static class InputTooLongException : Exception
    {
        mixin ReusableExceptionImplementation!();
    }

    /// ditto
    protected static InputTooLongException inputException;

    /***************************************************************************

        Static constructor.

    ***************************************************************************/

    static this ()
    {
        DhtCommand.inputException = new InputTooLongException;
    }


    /***************************************************************************
    
        Holds set of method to access temporary resources used by dhtnode
        protocol classes. Those all are placed into single class to simplify
        maintenance and eventually may be replaced with more automatic approach.

    ***************************************************************************/

    public interface Resources
    {
        mstring*            getChannelBuffer ( );
        mstring*            getKeyBuffer ( );
        mstring*            getFilterBuffer ( );
        mstring*            getValueBuffer ( );
        mstring*            getDecompressBuffer ( );
        ubyte[]*            getCompressBuffer ( );
        RecordBatcher       getRecordBatcher ( );
        RecordBatch         getRecordBatch ( );
        RedistributeNode[]* getRedistributeNodeBuffer ( );
    }

    /***************************************************************************

        Resource object instance defined by dhtproto implementor. Passed through
        constructor chain from request implementation classes.

    ***************************************************************************/

    protected Resources resources;

    /***************************************************************************

        Constructor

        Params:
            command = command code
            reader = FiberSelectReader instance to use for read requests
            writer = FiberSelectWriter instance to use for write requests
            resources = object providing resource getters

    ***************************************************************************/

    public this ( DhtConst.Command.E command, FiberSelectReader reader,
        FiberSelectWriter writer, Resources resources )
    {
        auto name = command in DhtConst.Command();
        assert(name);
        super(*name, reader, writer);

        assert(resources);
        this.resources = resources;
    }
}
