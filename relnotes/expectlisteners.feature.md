### New method to wait until a certain number of listeners are registered

`turtle.env.Dht`

App test suites typically need to wait for mirror/listen requests to start
before running any tests. To support this, the new method `Dht.expectListeners`
provides a means for waiting until a specified number of listeners are
registered with a specified list of channels. This allows app test suites to
implement test cases which would validate the mirror setup.

