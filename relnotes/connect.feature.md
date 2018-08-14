### Simple methods to connect to a node or cluster

`dhtproto.client.mixins.NeoSupport`

The blocking API now has three additional methods named `connect`. These add
either a single node (specified either by address & port or purely by port) or
a cluster of nodes (specified by a config file) to the registry, and then blocks
the current `Task` until the hash range of all nodes has been fetched.

These new methods are intended to simplify use of the DHT client in test code
and scripts.

