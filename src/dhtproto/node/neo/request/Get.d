/*******************************************************************************

    Get request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.Get;

/*******************************************************************************

    v0 Get request protocol.

*******************************************************************************/

public abstract scope class GetProtocol_v0
{
    import swarm.neo.node.RequestOnConn;
    import dhtproto.common.Get;
    import dhtproto.node.neo.request.core.Mixins;

    import ocean.transition;

    /***************************************************************************

        Mixin the constructor and resources member.

    ***************************************************************************/

    mixin RequestCore!();

    /***************************************************************************

        Request handler. Reads the record to be put from the client, adds it to
        the storage engine, and responds to the client with a status code.

        Params:
            connection = connection to client
            msg_payload = initial message read from client to begin the request
                (the request code and version are assumed to be extracted)

    ***************************************************************************/

    final public void handle ( RequestOnConn connection, Const!(void)[] msg_payload )
    {
        auto ed = connection.event_dispatcher();

        auto channel = ed.message_parser.getArray!(char)(msg_payload);
        auto key = *ed.message_parser.getValue!(hash_t)(msg_payload);

        void sendResponse ( MessageType status_code,
            void delegate ( ed.Payload ) extra = null )
        {
            ed.send(
                ( ed.Payload payload )
                {
                    payload.add(status_code);
                }
            );

            // TODO: this could be sent in the same message as the status code,
            // above. (Client would need to be adaptated.)
            if ( extra !is null )
                ed.send(extra);
        }

        // Check record key and read from channel, if ok.
        if ( this.responsibleForKey(key) )
        {
            bool sent;
            auto ok = this.get(channel, key,
                ( Const!(void)[] value )
                {
                    assert(value !is null);
                    assert(value.length);

                    sendResponse(MessageType.Got,
                        ( ed.Payload payload )
                        {
                            payload.addArray(value);
                        }
                    );

                    sent = true;
                }
            );

            if ( !sent )
                sendResponse(ok ? MessageType.NoRecord
                                : MessageType.Error);
        }
        else
            sendResponse(MessageType.WrongNode);

        ed.flush();
    }

    /***************************************************************************

        Checks whether the node is responsible for the specified key.

        Params:
            key = key of record to write

        Returns:
            true if the node is responsible for the key

    ***************************************************************************/

    abstract protected bool responsibleForKey ( hash_t key );

    /***************************************************************************

        Gets a single record from the storage engine.

        Params:
            channel = channel to read from
            key = key of record to read
            dg = called with the value of the record, if it exists

        Returns:
            true if the operation succeeded (the record was fetched or did not
            exist); false if an error occurred

    ***************************************************************************/

    abstract protected bool get ( cstring channel, hash_t key,
        void delegate ( Const!(void)[] value ) dg );
}
