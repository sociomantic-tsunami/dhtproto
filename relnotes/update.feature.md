### Neo Update request

`dhtproto.client.DhtClient`, `dhtproto.client.request.Update`

The new request, `Update`, fetches a record value, allows the user to specify an
updated value, and replaces the old value in the node with the new value. Note
that the request will notice if the value being updated has been modified by
another request, while the Update is in progress. If this happens, the Update
will be rejected (the client should retry the request).

