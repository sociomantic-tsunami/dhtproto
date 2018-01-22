Description
===========

``dhtproto`` is a library that contains the protocol for the Distributed Hash
Table (DHT), including:

* The DHT client (``src.dhtproto.client``).
* Base classes for the protocol handling parts of the DHT node
  (``src.dhtproto.node``).
* A simple, "fake" DHT node, for use in tests (``src.fakedht``).
* A turtle env extension (``src.turtle.env.Dht``) providing a fake DHT node for
  use in tests, including methods to inspect and modify its contents.
* A thorough test of the DHT protocol, using the client to connect to a node.
  The test is run, in this repo, on a fake node, but it can be reused in other
  repos to test real node implementations. (``src.dhttest``)

Dependencies
============

==========  =======
Dependency  Version
==========  =======
ocean       v3.1.4
swarm       v4.0.x
turtle      v8.0.x
==========  =======

Versioning
==========

dhtproto's versioning follows `Neptune
<https://github.com/sociomantic-tsunami/neptune/blob/master/doc/library-user.rst>`_.

This means that the major version is increased for breaking changes, the minor
version is increased for feature releases, and the patch version is increased
for bug fixes that don't cause breaking changes.

Support Guarantees
------------------

* Major branch development period: 6 months
* Maintained minor versions: 1 most recent

Maintained Major Branches
-------------------------

======= ==================== =============== =====
Major   Initial release date Supported until Notes
======= ==================== =============== =====
v13.x.x v13.0.0_: 01/08/2017 TBD             First open source release
======= ==================== =============== =====

.. _v13.0.0: https://github.com/sociomantic-tsunami/dhtproto/releases/tag/v13.0.0


Contributing
============

See the guide for `contributing to Neptune-versioned libraries
<https://github.com/sociomantic-tsunami/neptune/blob/master/doc/library-contributor.rst>`_.
