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

        RequestStatusCode response;

        // Check record key and read from channel, if ok.
        void[]* value;
        if ( this.responsibleForKey(key) )
        {
            value = this.resources.getVoidBuffer();
            if ( this.get(channel, key, *value) )
                response = value.length
                    ? RequestStatusCode.Got : RequestStatusCode.NoRecord;
            else
                response = RequestStatusCode.Error;
        }
        else
            response = RequestStatusCode.WrongNode;

        // Send status code
        ed.send(
            ( ed.Payload payload )
            {
                payload.add(response);
            }
        );

        // Send value, if retrieved
        if ( response == RequestStatusCode.Got )
        {
            assert(value !is null);
            assert(value.length);

            ed.send(
                ( ed.Payload payload )
                {
                    payload.addArray(*value);
                }
            );
        }
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
            channel = channel to write to
            key = key of record to write
            value = buffer to receive record value. If the record does not exist
                in the storage engine, value.length must be set to 0

        Returns:
            true if the operation succeeded (the record was fetched or did not
            exist); false if an error occurred

    ***************************************************************************/

    abstract protected bool get ( cstring channel, hash_t key, ref void[] value );
}
