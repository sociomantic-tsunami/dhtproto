# DHT Client Overview

This package contains the client to connect to a Distributed Hash Table
(DHT) database. The client is built on top of the framework provided by
[swarm](https://github.com/sociomantic-tsunami/swarm/). Swarm (and thus the DHT
client) currently supports two protocols, known as the "legacy protocol" and the
"neo procotol". Detailed documentation about the workings of swarm-based clients
and the two protocols can be found
[here (legacy protocol)](https://github.com/sociomantic-tsunami/swarm/blob/v4.x.x/src/swarm/README_client.rst)
and [here (neo protocol)](https://github.com/sociomantic-tsunami/swarm/blob/v4.x.x/src/swarm/README_client_neo.rst).

The legacy protocol is to be phased out, so the remainder of this README focuses
solely on the neo protocol.

## Usage examples

Detailed usage examples for all requests (and other features of the client) are
provided in [this module](UsageExamples.d).

## Requests

### Request API Modules

Each request has an API module in `src.dhtproto.client.request`, containing:

* A description of what the request does and how it works.
* The definition of the notifier delegate type for the request. (A notifier
  must be provided by the user, when assigning a request, and is called whenever
  anything of interest related to the request happens.)
* The smart union of notifications that is passed to the notifier. The active
  member of the union indicates the type of the notification and may carry
  additional information (e.g. the address/port of a node, an exception, etc).
* The ``Args`` struct which is passed to the notifier delegate, along with the
  notification. This contains a copy of all arguments which were specified by
  the user to start the request.

The request API modules provide a single, centralised point of documentation and
definitions pertaining to each request.

### Available Requests

The DHT supports the following requests (links to the API modules):

* [`Put`](request/Put.d):
  puts a record key and value to a channel.
* [`Get`](request/Get.d):
  gets a record, specified by its key, from a channel.
* [`Exists`](request/Exists.d):
  checks whether a record, specified by its key, exists in a channel.
* [`GetAll`](request/GetAll.d):
  gets the keys and values of all records in a channel.
* [`GetChannels`](request/GetChannels.d):
  gets the names of all channels.
* [`Mirror`](request/Mirror.d):
  receive a stream of updates (additions, changes, deletions) to records in a
  channel, including a periodic "refresh" of all records in the channel.

### Assigning Requests

The methods to assign requests are in the `DhtClient` class and defined in
[this module](mixins/NeoSupport.d). Note that there are two ways to assign some
requests:

1. Via the `DhtClient.neo` object. This assigns a request in the normal
   manner.
2. Via the `DhtClient.blocking` object. This assigns a request in a `Task`-
   blocking manner -- the current task will be suspended until the assigned
   request is finished.

