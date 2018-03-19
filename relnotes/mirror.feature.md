### New channel mirror helper with improved handling of connection errors

`dhtproto.client.legacy.internal.helper.Mirror`

The new channel mirror implementation deliberately has the same API as the old
one, allowing it to be used as a drop-in replacement. You should be able to
simply change imports of `dhtproto.client.legacy.internal.helper.ChannelMirror`
to `dhtproto.client.legacy.internal.helper.Mirror` and instantiate a `Mirror`
object, instead of a `ChannelMirror` object.

Notes:
* The new channel mirror does not reassign requests to connected nodes when
  there's an error on another connection. (This fixes a major problem in the old
  channel mirror.)
* The new channel mirror is thus also suitable for use with applications that
  start their main functionality after a partial DHT handshake.
* Due to the different internal implementation, the GetAll requests assigned by
  the new channel mirror may not be synchronised. This means that you can
  receive GetAll data from different nodes at different times. This is not
  expected to have any effect on applications, but is a noteworthy change in
  behaviour.

### Extensible channel mirror works with new channel mirror class

`dhtproto.client.legacy.internal.helper.ExtensibleChannelMirror`

The new template -- `ExtensibleMirror` -- allows the extensible mirror
functionality to be used with the new `Mirror` class. Usage like:
```D
alias ExtensibleChannelMirror!(SchedulingDhtClient,
    RawRecordDeserializer!(Record), DeserializedRecordCache!(Record))
    ExampleMirror;
```
should be changed to
```D
alias ExtensibleMirror!(SchedulingDhtClient, Mirror!(SchedulingDhtClient),
    RawRecordDeserializer!(Record), DeserializedRecordCache!(Record))
    ExampleMirror;
```

