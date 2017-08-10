* `dhtproto.client.mixins.NeoSupport`, `dhtproto.client.request.GetAll`

  The GetAll request now has a `Settings` struct which can be passed to the
  `getAll` method of the client. The following options exist:

    - `keys_only`: sets the request to only fetch the keys of records in the
      channel, not the values.
    - `value_filter`: filters out record values which do not contain the
      specified binary sequence.

