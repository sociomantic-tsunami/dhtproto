### New handshake helper with built-in task support

`dhtproto.client.legacy.internal.helper.Handshake`

The new `DhtHandshake` class wraps the existing `RetryHandshake` with
easy support for a task-based workflow.  This should make it easy for
applications to support a partial handshake, e.g.:

```D
auto retry_delay_seconds = 3;
auto handshake = new DhtHandshake(dht_client, retry_delay_seconds);

// block on at least one node connecting
theScheduler.await(handshake.oneNodeConnected());
Stdout.formatln("At least one node is now connected!");

// wait until either all nodes have connected, or 60 seconds
// have passed, whichever comes sooner (N.B. `awaitOrTimeout`
// is only available for more recent ocean releases)
auto timeout_microsec = 60_000_000;

auto handshake_timeout =   // true if timeout is reached
    theScheduler.awaitOrTimeout(
        handshake.allNodesConnected(),
        timeout_microsec);

if (handshake_timeout)
{
    Stdout.formatln(
        "DHT handshake did not succeed within {} seconds!",
        timeout_microsec / 1_000_000);
}
else
{
    Stdout.formatln(
        "DHT handshake reached all nodes before timeout!");
}

// if we timed out, the `DhtHandshake` instance will still
// keep working in the background to connect to the missing
// DHT nodes, so all nodes should be reached eventually
```
