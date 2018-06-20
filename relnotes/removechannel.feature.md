### Neo RemoveChannel request

`dhtproto.client.DhtClient`, `dhtproto.client.request.RemoveChannel`

The new request, `RemoveChannel`, allows a complete channel to be removed from
all nodes in a DHT.

Note:
  * The real DHT implementation will reject this request if it is sent by a
    non-admin client. For testing convenience, the fake DHT in this repo allows
    any client to remove channels.

