* `dhtproto.client.DhtClient`

  New constructors have been added (including to the derived classes
  `ExtensibleDhtClient` and `SchedulingDhtClient`) that accept an instance of
  `Neo.Config` (see `dhtproto.client.mixins.NeoSupport`). The config instance is
  expected to have been read in from a config file using
  `ocean.util.config.ConfigFiller`.

