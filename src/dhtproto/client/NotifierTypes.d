/*******************************************************************************

    DHT-specific types passed to client request notifier delegates.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.NotifierTypes;

import ocean.transition;
import Formatter = ocean.text.convert.Formatter;

/*******************************************************************************

    A chunk of untyped data along with a key.

*******************************************************************************/

public struct RequestRecordInfo
{
    import swarm.neo.protocol.Message : RequestId;
    import swarm.neo.client.mixins.DeserializeMethod;

    /// ID of the request for which the notification is occurring.
    RequestId request_id;

    /// Record key.
    hash_t key;

    /// Record value.
    Const!(void)[] value;

    /// Template method to deserialize `value` as a given struct.
    mixin DeserializeMethod!(value);

    /***************************************************************************

        Formats a description of the notification to the provided sink delegate.

        Params:
            sink = delegate to feed formatted strings to

    ***************************************************************************/

    public void toString ( scope void delegate ( cstring chunk ) sink )
    {
        Formatter.sformat(
            sink,
            "Request #{} provided the record 0x{:x16}:{}",
            (&this).request_id, (&this).key, (&this).value);
    }
}

/*******************************************************************************

    A chunk of untyped data along with a pointer to a buffer to receive a
    modified version.

*******************************************************************************/

public struct RequestDataUpdateInfo
{
    import swarm.neo.protocol.Message : RequestId;
    import swarm.neo.client.mixins.DeserializeMethod;

    /// ID of the request for which the notification is occurring.
    RequestId request_id;

    /// Record value.
    Const!(void)[] value;

    /// Buffer to receive updated value.
    void[]* updated_value;

    /// Template method to deserialize `value` as a given struct.
    mixin DeserializeMethod!(value);

    /// Template method to serialize a given struct into `updated_value`.
    mixin SerializeMethod!(updated_value);

    /***************************************************************************

        Formats a description of the notification to the provided sink delegate.

        Params:
            sink = delegate to feed formatted strings to

    ***************************************************************************/

    public void toString ( scope void delegate ( cstring chunk ) sink )
    {
        Formatter.sformat(
            sink,
            "Request #{} provided the record {} to be updated",
            (&this).request_id, (&this).value);
    }
}

/*******************************************************************************

    A record key.

*******************************************************************************/

public struct RequestKeyInfo
{
    import swarm.neo.protocol.Message : RequestId;

    /// ID of the request for which the notification is occurring.
    RequestId request_id;

    /// Record key.
    hash_t key;

    /***************************************************************************

        Formats a description of the notification to the provided sink delegate.

        Params:
            sink = delegate to feed formatted strings to

    ***************************************************************************/

    public void toString ( scope void delegate ( cstring chunk ) sink )
    {
        Formatter.sformat(
            sink,
            "Request #{} provided the key 0x{:x16}",
            (&this).request_id, (&this).key);
    }
}

/*******************************************************************************

    Mixin for method to serialize a record value.

    Params:
        dst = pointer to the buffer to be serialized into

    TODO: deprecated, replace with implementation in swarm

*******************************************************************************/

template SerializeMethod ( alias dst )
{
    import ocean.util.serialize.contiguous.Contiguous;
    import ocean.util.serialize.Version;
    import ocean.util.serialize.contiguous.Serializer;
    import ocean.util.serialize.contiguous.MultiVersionDecorator;

    /***************************************************************************

        Serializes `src` into `dst`, using a version decorater, if required.

        Params:
            T = type of struct to serialize
            src = instance to serialize

    ***************************************************************************/

    public void serialize ( T ) ( T src )
    {
        static if ( Version.Info!(T).exists )
            VersionDecorator.store!(T)(src, *dst);
        else
            Serializer.serialize(src, *dst);
    }
}
