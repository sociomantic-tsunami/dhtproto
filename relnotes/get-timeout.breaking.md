* `dhtproto.client.request.Get`

  The notification union for Get requests now includes an additional field:
  `timed_out`. Get notifiers should be updated to handle this field (a simple
  `case timed_out: break;` is sufficient, if your application is not using Get
  timeouts).

