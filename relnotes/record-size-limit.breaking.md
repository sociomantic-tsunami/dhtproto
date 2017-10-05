* `dhtproto.client.request.Put`

  The neo Put request now enforces a size limit on record values written to the
  DHT. Any record value which is larger than the constant defined in this module
  will be rejected. The user will be notified of this via the new
  `value_too_big` notifier.

  Put notifiers in existing code should be updated to handle the new
  notification type as appropriate.

