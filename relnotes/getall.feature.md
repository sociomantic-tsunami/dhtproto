* `dhtproto.client.DhtClient : Neo`, `dhtproto.client.request.GetAll`

  The new GetAll request provides a way to fetch a snapshot of all records in a
  channel. If the request is interrupted (e.g. by a connection error), it is
  automatically restarted and continues where it left off.

