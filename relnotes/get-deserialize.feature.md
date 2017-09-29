* `dhtproto.client.request.Get`, `dhtproto.client.request.GetAll`,
  `dhtproto.client.request.Mirror`

  The Get, GetAll, and Mirror request notifications that provide a record value
  (with or without an associated key) to the user now expose a method template
  called `deserialize`. This method provides a simple API for deserializing
  DHT records to a specific struct type, using
  `ocean.util.serialize.contiguous.Deserializer`.

