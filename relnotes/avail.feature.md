### New legacy client tracker for node availability

`dhtproto.client.legacy.internal.helper.NodeAvailability`

This helper is useful in apps that have a data flow pattern like the following:
    1. Receive a record from an incoming source (e.g. a DMQ channel).
    2. Do some expensive but non-critical processing on the record. (e.g.
       querying an external service.)
    3. Write the results of the processing to the DHT.

By tracking which DHT nodes have had connectivity problems recently, the app
can decide to not perform step 2 at all, if the DHT node to which the result
would be written is inaccessible. (i.e. discarding the request, rather than
queuing up the write to be performed when the DHT node becomes accessible.)

