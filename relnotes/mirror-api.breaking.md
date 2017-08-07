* `dhtproto.client.DhtClient : Neo`, `dhtproto.client.request.Mirror`

  The API of the Mirror request has changed such that it is no longer possible
  to start a Mirror request which does not stream live updates from the node to
  the client. The `Settings.live_updates` flag has been removed, along with the
  `finished` notification. Now, the only way for a Mirror request to end is if
  the user stops it (or the channel being mirrorred is removed).

