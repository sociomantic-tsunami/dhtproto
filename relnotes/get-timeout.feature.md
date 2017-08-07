* `dhtproto.client.DhtClient : Neo`

  The `get` method now accepts an optional argument of type `Neo.Get.Timeout`,
  specifying a milliseconds timeout value. If the request has not completed
  before the timeout expires, the request is aborted and the notifier called
  with the `timed_out` notification.

