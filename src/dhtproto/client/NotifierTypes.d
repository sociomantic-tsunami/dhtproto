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

    /// ID of the request for which the notification is occurring.
    RequestId request_id;

    /// Record key.
    hash_t key;

    /// Record value.
    Const!(void)[] value;

    /***************************************************************************

        Formats a description of the notification to the provided sink delegate.

        Params:
            sink = delegate to feed formatted strings to

    ***************************************************************************/

    public void toString ( void delegate ( cstring chunk ) sink )
    {
        Formatter.sformat(
            sink,
            "Request #{} provided the record 0x{:x16}:{}",
            this.request_id, this.key, this.value);
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

    public void toString ( void delegate ( cstring chunk ) sink )
    {
        Formatter.sformat(
            sink,
            "Request #{} provided the key 0x{:x16}",
            this.request_id, this.key);
    }
}
