/*******************************************************************************

    Update request protocol.

    Copyright:
        Copyright (c) 2018 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.node.neo.request.Update;

import ocean.core.VersionCheck;
import swarm.neo.node.IRequest;

/*******************************************************************************

    v0 Update request protocol.

*******************************************************************************/

public abstract class UpdateProtocol_v0 : IRequest
{
    import swarm.neo.node.RequestOnConn;
    import dhtproto.common.Update;
    import dhtproto.node.neo.request.core.Mixins;

    import ocean.transition;
    import ocean.core.array.Mutation : copy;
    import ocean.io.digest.Fnv1;

    /// Mixin the initialiser and the connection and resources members.
    mixin IRequestHandlerRequestCore!();

    /// Slice of acquired buffer into which the initial payload received from
    /// the client is copied.
    private const(void)[] init_payload;

    /***************************************************************************

        Called by the connection handler after the request code and version have
        been parsed from a message received over the connection, and the
        request-supported code sent in response.

        Note: the initial payload passed to this method is a slice of a buffer
        owned by the RequestOnConn. It is thus safe to assume that the contents
        of the buffer will not change over the lifetime of the request.

        Params:
            connection = request-on-conn in which the request handler is called
            resources = request resources acquirer
            init_payload = initial message payload read from the connection

    ***************************************************************************/

    public void handle ( RequestOnConn connection, Object resources,
        const(void)[] init_payload )
    {
        this.initialise(connection, resources);

        auto buf = this.resources.getVoidBuffer();
        (*buf).copy(init_payload);
        this.init_payload = *buf;

        auto ed = this.connection.event_dispatcher();

        auto message =
            *ed.message_parser.getValue!(MessageType)(this.init_payload);
        auto channel = ed.message_parser.getArray!(char)(this.init_payload);
        auto key = *ed.message_parser.getValue!(hash_t)(this.init_payload);

        MessageType response;

        if ( this.responsibleForKey(key) )
        {
            with ( MessageType ) switch ( message )
            {
                // Normal sequence: read, wait for response, update.
                case GetRecord:
                    response = this.getWaitUpdate(channel, key);
                    break;

                // Either an updated record transferred from another node or a
                // new record that did not exist in the DHT before. Just put it.
                case UpdateRecord:
                    response = this.update(channel, key, this.init_payload);
                    break;

                default:
                    ed.shutdownWithProtocolError("Unexpected message from client");
            }
        }
        else
            response = MessageType.WrongNode;

        // Send the final message to the client.
        ed.send(
            ( ed.Payload payload )
            {
                payload.add(response);
            }
        );

        static if (!hasFeaturesFrom!("swarm", 4, 7))
            ed.flush();
    }

    /***************************************************************************

        Normal sequence: get, wait for response, update.

        Params:
            channel = channel to update record in
            key = key of record to update

        Returns:
            message type code to return to the client

    ***************************************************************************/

    private MessageType getWaitUpdate ( cstring channel, hash_t key )
    {
        auto ed = this.connection.event_dispatcher();

        // Get record value from storage and send it to the client.
        bool exists;
        auto success = this.get(channel, key,
            ( const(void)[] value )
            {
                exists = true;

                ed.send(
                    ( ed.Payload payload )
                    {
                        payload.addCopy(MessageType.RecordValue);
                        payload.addArray(value);
                    }
                );

                static if (!hasFeaturesFrom!("swarm", 4, 7))
                    ed.flush();
            }
        );

        // If getting the record failed, end the request.
        if ( !success )
            return MessageType.Error;

        // If the record did not exist, end the request.
        if ( !exists )
            return MessageType.NoRecord;

        // Wait for the client's response.
        MessageType ret;
        ed.receive(
            ( const(void)[] payload )
            {
                const(void)[] payload_slice = payload;

                auto message = *ed.message_parser.getValue!(MessageType)(
                    payload_slice);
                with ( MessageType ) switch ( message )
                {
                    // Client wants to update the record.
                    case UpdateRecord:
                        ret = this.update(channel, key, payload_slice);
                        break;

                    // Client has decided not to update the record.
                    case LeaveRecord:
                        ret = MessageType.Ok;
                        break;

                    // Client has sent the updated record to another node. It
                    // can be removed here.
                    case RemoveRecord:
                        ret = this.remove(channel, key)
                            ? MessageType.Ok : MessageType.Error;
                        break;

                    default:
                        ed.shutdownWithProtocolError("Unexpected message from client");
                }
            }
        );

        return ret;
    }

    /***************************************************************************

        1. Parses the hash of the original record value and the updated record
           value from the message payload.
        2. Gets the record value from storage and hashes it.
        3. Compares the hash of the original value (provided by the client) with
           the hash of the value in storage.
        4a. If the hashes differ, the record has been updated by another client.
            The request is rejected.
        4b. If the hashes match, the new value is written to storage.

        Params:
            channel = channel to update record in
            key = key of record to update
            payload = message payload received from client; contains the orignal
                hash of the record value and the new record value

        Returns:
            message type code to return to the client

    ***************************************************************************/

    private MessageType update ( cstring channel, hash_t key,
        const(void)[] payload )
    {
        // Read original record value hash and updated value from client.
        auto ed = this.connection.event_dispatcher();
        hash_t original_hash;
        const(void)[] new_value;
        ed.message_parser.parseBody(payload, original_hash, new_value);

        // Get the currently stored record value and hash it.
        bool exists;
        hash_t stored_hash;
        auto ok = this.get(channel, key,
            ( const(void)[] value )
            {
                exists = true;
                stored_hash = Fnv1a(value);
            }
        );
        if ( !ok )
            return MessageType.Error;

        // Check for update conflicts.
        if ( exists && stored_hash != original_hash )
            return MessageType.UpdateConflict;

        // Otherwise, write the updated record value to storage.
        return this.put(channel, key, new_value)
            ? MessageType.Ok : MessageType.Error;
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

        Reads a single record from the storage engine. Note that the
        implementing class must guarantee that no fiber switch can occur during
        this method.

        Params:
            channel = channel to read from
            key = key of record to read
            dg = called with the value of the record, if it exists

        Returns:
            true if the operation succeeded (the record was fetched or did not
            exist); false if an error occurred

    ***************************************************************************/

    abstract protected bool get ( cstring channel, hash_t key,
        scope void delegate ( const(void)[] value ) dg );

    /***************************************************************************

        Writes a single record to the storage engine.

        Params:
            channel = channel to write to
            key = key of record to write
            value = record value to write

        Returns:
            true if the record was written; false if an error occurred

    ***************************************************************************/

    abstract protected bool put ( cstring channel, hash_t key, in void[] value );

    /***************************************************************************

        Removes a single record from the storage engine.

        Params:
            channel = channel to remove to
            key = key of record to remove

        Returns:
            true if the record was removed; false if an error occurred

    ***************************************************************************/

    abstract protected bool remove ( cstring channel, hash_t key );
}
