### New, ultra-minimal client ctor for use in scripts/tests

`dhtproto.client.DhtClient`

The existing constructors require an epoll instance and various user-specified
configuration settings. The newly added constructor allows a DHT client to be
instantiated with no configuration whatsoever:

```
auto dht = new DhtClient; // uses Task-scheduler's epoll instance
```

This greatly reduces the amount of boilerplate required to use a DHT client in
a script or test.

