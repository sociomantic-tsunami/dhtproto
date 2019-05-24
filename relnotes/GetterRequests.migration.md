### Request getters return values via delegates

`dhtproto.node.request.Get`, `dhtproto.node.request.GetChannelSize`,
`dhtproto.node.request.GetChannels`, `dhtproto.node.request.GetNumConnections`,
`dhtproto.node.request.GetResponsibleRange`, `dhtproto.node.request.GetSize`,
`fakedht.request.Get`, `fakedht.request.GetChannelSize`,
`fakedht.request.GetChannels`, `fakedht.request.GetNumConnections`,
`fakedht.request.GetResponsibleRange`, `fakedht.request.GetSize`

This improves performance by reducing by one the number of times the
value(s) gets copied before being returned.
