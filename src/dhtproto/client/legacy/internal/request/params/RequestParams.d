/*******************************************************************************

    Parameters for a dht request.

    Copyright:
        Copyright (c) 2010-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.request.params.RequestParams;



/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import swarm.client.request.params.IChannelRequestParams;

import swarm.client.request.context.RequestContext;

import swarm.client.ClientCommandParams;

import swarm.client.request.model.ISuspendableRequest;

import swarm.client.connection.model.INodeConnectionPoolInfo;

import dhtproto.client.legacy.internal.request.params.IODelegates;

import dhtproto.client.legacy.DhtConst;

import dhtproto.client.legacy.internal.request.notifier.RequestNotification;

import ocean.core.SmartUnion;
import ocean.core.Traits;

import swarm.util.Hash;




public class RequestParams : IChannelRequestParams
{
    /***************************************************************************

        Local type redefinitions

    ***************************************************************************/

    public alias .PutValueDg PutValueDg;
    public alias .PutBatchDg PutBatchDg;
    public alias .GetValueDg GetValueDg;
    public alias .GetPairDg GetPairDg;
    public alias .GetBoolDg GetBoolDg;
    public alias .GetResponsibleRangeDg GetResponsibleRangeDg;
    public alias .GetNumConnectionsDg GetNumConnectionsDg;
    public alias .GetNodeValueDg GetNodeValueDg;
    public alias .GetSizeInfoDg GetSizeInfoDg;
    public alias .GetChannelSizeInfoDg GetChannelSizeInfoDg;
    public alias .RegisterSuspendableDg RegisterSuspendableDg;
    public alias .RegisterStreamInfoDg RegisterStreamInfoDg;
    public alias .RedistributeDg RedistributeDg;

    public alias swarm.util.Hash.HexDigest HexDigest;


    /**************************************************************************

        Request hash

     **************************************************************************/

    public hash_t hash;

    /***************************************************************************

        Request I/O delegate union

    ***************************************************************************/

    public union IODg
    {
        PutValueDg put_value;
        PutBatchDg put_batch;
        GetValueDg get_value;
        GetPairDg get_pair;
        GetBoolDg get_bool;
        GetResponsibleRangeDg get_hash_range;
        GetSizeInfoDg get_size_info;
        GetChannelSizeInfoDg get_channel_size;
        GetNumConnectionsDg get_num_connections;
        GetNodeValueDg get_node_value;
        RedistributeDg redistribute;
    }

    public alias SmartUnion!(IODg) IOItemUnion;

    public IOItemUnion io_item;


    /***************************************************************************

        Request filter string

    ***************************************************************************/

    public cstring filter;


    /***************************************************************************

        Delegate which receives an ISuspendable interface when a suspendable
        request has just started.

    ***************************************************************************/

    public RegisterSuspendableDg suspend_register;


    /***************************************************************************

        Delegate which receives an IStreamInfo interface when a stream request
        has just started.

    ***************************************************************************/

    public RegisterStreamInfoDg stream_info_register;


    /**************************************************************************

        Generates the hexadecimal string representation of the current key.
        This asserts that the key is currently set to a hash_t value.

        Params:
            hash = destination string

        Returns:
            destination string containing the result

     **************************************************************************/

    public mstring keyToString ( mstring hash )
    {
        return toHexString(this.hash, hash);
    }


    /***************************************************************************

        News a dht client RequestNotification instance and passes it to the
        provided delegate.

        Params:
            info_dg = delegate to receive IRequestNotification instance

    ***************************************************************************/

    override protected void notify_ ( scope void delegate ( IRequestNotification ) info_dg )
    {
        scope info = new RequestNotification(cast(DhtConst.Command.E)this.command,
            this.context);
        info_dg(info);
    }


    /***************************************************************************

        Copies the fields of this instance from another.

        All fields are copied by value. (i.e. all arrays are sliced.)

        Note that the copyFields template used by this method relies on the fact
        that all the class' fields are non-private. (See template documentation
        in ocean.core.Traits for further info.)

        Params:
            params = instance to copy fields from

    ***************************************************************************/

    override protected void copy__ ( IRequestParams params )
    {
        auto dht_params = cast(RequestParams)params;
        copyClassFields(this, dht_params);
    }


    /***************************************************************************

        Add the serialisation override methods

    ***************************************************************************/

    mixin Serialize!();
}
