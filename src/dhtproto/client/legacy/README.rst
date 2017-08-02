.. contents ::

Introduction and Core Concepts
================================================================================

Please read the core client documentation before proceeding. This README
only describes features specific to the DHT client.

The DHT client enables asynchronous communication with a Distributed Hash Table
(DHT) key-value database. The record keys are 64-bit integers (commonly created
by hashing longer values). The record values are arbitrary data of up to 64K in
size. A DHT can be spread over multiple 'nodes', each node being responsible for
a fixed subset of the complete range of possible keys (i.e. the range of
unsigned 64-bit integers).

Basic DHT Client Usage
================================================================================

Empty Records
--------------------------------------------------------------------------------

It is not possible to store empty records in the DHT. The client checks this and
will cancel the request if the user attempts to Put an empty record.

Get Delegates
--------------------------------------------------------------------------------

Requests which read data from the DHT must provide a delegate which is to be
called when the data is received. Requests which read multiple pieces of data
from the DHT (GetAll, for example) will result in the provided delegate being
called multiple times, once for each piece of data received.

Put Delegates
--------------------------------------------------------------------------------

Requests which write data to the DHT must provide a delegate which is to be
called when the client is ready to send the data for the request, and must
return the data to be sent.

Note that the data provided by the put delegate is only sliced by the DHT
client, and must remain available until the request finished notification is
received.

Iteration Requests
--------------------------------------------------------------------------------

Several DHT requests (GetAll and GetAllKeys, for example) result in an iteration
over the complete set of records stored in a DHT channel. These requests are
executed in parallel on all nodes in the DHT, and thus will receive the
requested data at a much faster rate than if the data was iterated over in a
strictly sequential fashion. This does of course have the side-effect, however,
that the iterated data is *not* received in order. Thus the client application
must do any sorting of the recieved data which is required.

The Node Handshake
--------------------------------------------------------------------------------

Before any requests can be performed, the DHT client must make an initial query
to all nodes in the DHT. This 'node handshake' establishes which DHT nodes are
responsible for which subset of the key range and the API version of the node.

The ``nodeHandshake()`` method accepts a delegate which will be called upon
completion of the handshake. The delegate indicates whether the handshake
completed successfully for all nodes in the DHT or not. It also accepts a
request notifier, like all request methods, which will be called multiple times
while the handshake is underway.

The epoll event loop must be active / activated for the node handshake to start.

In the case of a partially successful handshake (some nodes responded while
others did not), it is still possible to use the DHT client but requests which
would be sent to the nodes which did not successfully handshake will be
rejected.

Basic Usage Example
--------------------------------------------------------------------------------

See dhtproto.client.DhtClient module header.

Advanced Client Features
================================================================================

Request Contexts in the DHT Client
--------------------------------------------------------------------------------

If the user does not specify a context for a request, the default context is the
key which the request is querying, if one is given (a ``hash_t``).

Usage Example With RequestContext
--------------------------------------------------------------------------------

In this example we receive and store all records from all channels in a DHT.
(This is not recommended in the real world, it is just given as a simple
example.) First the list of channels is queried from the DHT, then for each
channel we initiate a GetAll, passing a single delegate which will receive the
records from all channels. The problem now is: when the delegate is invoked
after receiving a value from the DHT, how do we know which channel the record is
part of? The ``RequestContext`` is used to solve this problem, using it as a
means of identifying the record's channel.

(Note that the DHT client initialisation and some other code in this example is
somewhat compressed, for the sake of brevity.)

.. code-block:: D

    import ocean.io.select.EpollSelectDispatcher;
    import dhtproto.client.internal.request.params.RequestParams;
    import dhtproto.client.DhtClient;
    import ocean.core.Array : appendCopy;
    import ocean.core.Array_tango : contains;

    void main()
    {
        // Request notification callback
        void notify ( DhtClient.RequestNotification info )
        {
            // normally an application should care about the info
        }

        // Handshake callback
        void handshake ( DhtClient.RequestContext context, bool ok )
        {
            // normally an application should care about the value of ok
        }

        // Initialise epoll
        auto epoll = new EpollSelectDispatcher;

        // Initialise DHT client
        auto dht = new DhtClient(epoll);
        dht.addNodes("etc/dht.nodes");
        dht.nodeHandshake(&handshake, &notify);
        epoll.eventLoop();

        // Array to receive the names of the channels which exist in the DHT
        char[][] channels;

        // Array to receive the DHT records, per channel
        char[][char[]] channel_records;

        // Callback delegate to receive channel names.
        // Stores the received names in the 'channels' array, making sure no
        // duplicates exist.
        void receive_channel ( DhtClient.RequestContext context, char[], ushort, char[] channel )
        {
            if ( channel.length && !channels.contains(channel) )
            {
                channels.appendCopy(channel);
            }
        }

        // Get the names of all channels in the DHT.
        dht.assign(dht.getChannels(&receive_channel, &notify));
        epoll.eventLoop();

        // Callback delegate to receive records.
        // Puts the received records into the list for the appropriate channel,
        // as indicated by the value stored in the request context.
        void receive_record ( DhtClient.RequestContext context, char[] key, char[] value )
        {
            // Retrieve the channel name by using the context as the index
            // into the 'channels' array
            auto channel_name = channels[context.integer];

            // Add record value to the channel's list.
            channel_records[channel_name] ~= value;
        }

        // 'channels' now contains a unique list of channel names. We iterate
        // over the channels and register a getAll request for each.:
        foreach ( channel_index, channel; channels )
        {
            // The request context is used to pass an index into the array of
            // channel names.
            dht.assign(dht.getAll(channel, &receive_record, &notify).context(channel_index));
        }

        // The getAll requests are activated in parallel.
        epoll.eventLoop;
    }

Record Filtering
--------------------------------------------------------------------------------

Certain requests (currently GetAll) support the passing of an optional filter
string to the node, via the request object's ``filter()`` method. This instructs
the node to only return records whose values contain the specified filter
string, and can be used to greatly reduce the bandwidth required when iterating
over large quantities of data.

