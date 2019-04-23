/*******************************************************************************

    Dht Client & Node Constants

    Copyright:
        Copyright (c) 2009-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.DhtConst;



/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.core.Enum;

import swarm.Const;
import swarm.util.Hash : HashRange;

import swarm.util.RecordBatcher;

import ocean.core.Tuple;

import ocean.transition;

/*******************************************************************************

    DhtConst (used as a namespace, all members static)

*******************************************************************************/

public struct DhtConst
{
static:

    /***************************************************************************

        Api version -- this number should be changed whenever the api is
        modified.

        IMPORTANT !!!

            If you change this api version number, please also create an svn tag
            for the old version, so that it's easy to compile code with old dht
            api versions.

        IMPORTANT !!!

    ***************************************************************************/

    public const ApiVersion = "20110401";


    /***************************************************************************

        Maximum record size accepted by the dht node. Set to the size of a bulk
        request batch so that all records can fit inside a batch.

    ***************************************************************************/

    public const RecordSizeLimit = RecordBatcher.DefaultMaxBatchSize;


    /***************************************************************************

        Command Code definitions

        Put                 = add record
        Get                 = retrieve record
        Exists              = checks for the existence of a record
        Remove              = remove record
        GetAll              = get all records from a DHT node
        GetAllKeys          = get the keys of all records in the DHT node
        GetChannels         = get the channels in the DHT node
        GetChannelSize      = get the total number of records and the
                              total size (in bytes) in a specified channel
        GetSize             = get the total number of records and the
                              total size (in bytes) of all records in
                              all channels
        GetResponsibleRange = get the minimum and maximum hash values
                              served by the DHT node
        RemoveChannel       = remove complete contents of a channel
        GetNumConnections   = gets the current number of active connections
                              from a DHT node
        GetVersion          = requests that the DHT node sends its api version
        Listen              = requests that the node sends a copy of any records
                              which have changed to the client
        GetAllFilter        = get all records from a DHT node which contain the
                              specified filter string
        Redistribute        = instructs a dht node to change its hash range and
                              redistribute its data to the specified nodes
        PutBatch            = adds a compressed batch of records (the node
                              decompresses the batch and adds each record)

    ***************************************************************************/

    // TODO: upon API change, the codes can be re-ordered, closing the gaps
    // where dead commands have been removed

    public class Command : ICommandCodes
    {
        mixin EnumBase!([
            "Put"[]:                    1,  // 0x01
            "Get":                      7,  // 0x07
            "Exists":                   11, // 0x0b
            "Remove":                   12, // 0x0c
            "GetChannels":              17, // 0x11
            "GetChannelSize":           18, // 0x12
            "GetSize":                  19, // 0x13
            "GetResponsibleRange":      20, // 0x14
            "RemoveChannel":            22, // 0x16
            "GetNumConnections":        23, // 0x17
            "GetVersion":               24, // 0x18
            "Listen":                   25, // 0x19
            "GetAll":                   29, // 0x1d
            "GetAllKeys":               30, // 0x1e
            "GetAllFilter":             31, // 0x1f
            "Redistribute":             33, // 0x21
            "PutBatch":                 34  // 0x22
        ]);
    }


    /***************************************************************************

        Status Code definitions (sent from the node to the client)

        Code 0   = Uninitialised value, never returned by the node.
        Code 200 = Node returns OK when request was fulfilled correctly.
        Code 400 = Node throws this error when the received  command is not
                   recognized.
        Code 404 = Node throws this error in case you try to add a hash key to a
                   node that is not responsible for this hash.
        Code 407 = Out of memory error in node (size limit exceeded).
        Code 408 = Attempted to put an empty value (which is illegal).
        Code 409 = Request channel name is invalid.
        Code 500 = This error indicates an internal node error.

    ***************************************************************************/

    public alias IStatusCodes Status;


    /***************************************************************************

        Node Item

    ***************************************************************************/

    public alias .NodeItem NodeItem;
}



/*******************************************************************************

    Node address/hash range wrapper struct, used by Redistribute request.

*******************************************************************************/

public struct NodeHashRange
{
    /***************************************************************************

        IP address / port of node

    ***************************************************************************/

    public NodeItem node;


    /***************************************************************************

        Hash responsibility range of node

    ***************************************************************************/

    public HashRange range;


    /***************************************************************************

        opCmp for sorting. Compares node address/port first, then hash range.

        Params:
            other = other NodeHashRange to compare against

        Returns:
            < 0 if this < other
            > 0 if this > other
            0 if this == other

    ***************************************************************************/

    mixin (genOpCmp(`
    {
        auto node_cmp = this.node.opCmp(rhs.node);
        if ( node_cmp == 0 )
        {
            return this.range.opCmp(rhs.range);
        }
        else
        {
            return node_cmp;
        }
    }`));

    /***************************************************************************

        opEquals defined in terms of opCmp

    ***************************************************************************/

    public equals_t opEquals ( NodeHashRange rhs )
    {
        return this.opCmp(rhs) == 0;
    }
}
