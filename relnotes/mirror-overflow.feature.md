* `dhtproto.client.request.Mirror`

  A new notification type -- `updates_lost` -- has been added. The node sends
  this notification to the client when its internal queue of updates to be sent
  overflows. This means that at least one update has not been sent to the
  mirroring client and indicates that there's a disparity between the rate at
  which updates are being made to the mirrored channel and the rate at which the
  Mirror request is able to inform the client of these updates.

