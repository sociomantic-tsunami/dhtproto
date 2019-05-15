### Neo node request classes now implement `IRequest`

`dhtproto.node.neo.request.Exists`, `dhtproto.node.neo.request.Get`,
`dhtproto.node.neo.request.GetAll`,`dhtproto.node.neo.request.GetChannels`,
`dhtproto.node.neo.request.GetHashRange`, `dhtproto.node.neo.request.Mirror`,
`dhtproto.node.neo.request.Put`, `dhtproto.node.neo.request.Remove`,
`dhtproto.node.neo.request.RemoveChannels`, `dhtproto.node.neo.request.Update`

All classes handling neo node requests now implement the `IRequest` interface in
the module `swarm.neo.node.IRequest`. As enforced by the `IRequest` interface's
definition, these classes implement the `handle` method. As these classes do not
implement the `IRequestHandler` interface, the methods `preSupportedCodeSent`
and `postSupportedCodeSent` methods are not implemented here anymore.
