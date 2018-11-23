### Add delegate to unregister RequestSuspender

* `dhtproto.client.legacy.internal.request.model.IBulkGetRequest`
* `dhtproto.client.legacy.internal.request.params.RequestParams`

This new delegate should be used to remove an ISuspendable
instance from a list of ISuspendables when a request finishes.
