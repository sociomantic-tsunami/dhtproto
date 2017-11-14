/*******************************************************************************

    Exists request protocol.

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.Exists;

/*******************************************************************************

    v0 Exists request protocol.

*******************************************************************************/

public abstract scope class ExistsProtocol_v0
{
    import swarm.neo.node.RequestOnConn;
    import dhtproto.common.Exists;
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

        MessageType response;

        // Check record key and read from channel, if ok.
        if ( this.responsibleForKey(key) )
        {
            bool found;
            if ( this.exists(channel, key, found) )
                response = found
                    ? MessageType.RecordExists : MessageType.NoRecord;
            else
                response = MessageType.Error;
        }
        else
            response = MessageType.WrongNode;

        // Send status code
        ed.send(
            ( ed.Payload payload )
            {
                payload.add(response);
            }
        );
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

        Checks whether a single record exists in the storage engine.

        Params:
            channel = channel to check in
            key = key of record to check
            found = out value, set to true if the record exists

        Returns:
            true if the operation succeeded; false if an error occurred

    ***************************************************************************/

    abstract protected bool exists ( cstring channel, hash_t key, out bool found );
}
