### New helper to dump and load a cached channel to/from disk

`dhtproto.client.helper.ChannelSerializer`

The new helper class is designed for use by applications that require a complete
copy of some DHT channel before they are able to start operating. In the case of
a DHT outage (either partial or complete), getting a fresh copy of a channel is
not possible, but many apps can function perfectly well with a copy of the
channel that was previously saved to disk.

The helper has methods to dump and load from/to associative arrays and `Map`s
(see `ocean.util.container.map.Map`), or from/to any arbitrary container that
supports iterating over and inserting <`hash_t`, `Contiguous!(S)`> records.

Usage examples: see documented unittests in the module.

