## RemoveChannel now fails if channel is being listened to

`dhtproto.node.request.RemoveChannel`

The behaviour of the RemoveChannel request has changed: the node will now reject
the request, returning an `Error` status code, if the channel to be removed has
an active listener (i.e. a Listen request).

This change is intended to protect active channels by preventing them from being
removed. If you genuinely want to remove a channel, please stop all listening
applications first.

