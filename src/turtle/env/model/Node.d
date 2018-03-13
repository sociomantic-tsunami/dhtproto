/*******************************************************************************

    Abstract fake node for integration with turtle's registry of env additions.

    TODO: this module will be included in a future major release of swarm. When
    available in swarm, this module should be removed.

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module turtle.env.model.Node;

import ocean.transition;
import turtle.env.model.Registry;

/*******************************************************************************

    Abstract fake node for integration with trutle's registry of env additions.

    Also includes methods for starting and stopping the fake node.

    Note: this class and derivatives are only used when running tests which need
    to *access* a node (the turtle env addition provides a fake node which can
    be inspected and modified by test cases). It is not relevant when running
    tests *on* a node implementation itself.

    Params:
        NodeType = type of the node server implementation
        id = name of the node type. Used for .nodes file name formatting

*******************************************************************************/

public abstract class Node ( NodeType, istring id ) : ITurtleEnv
{
    import swarm.Const : NodeItem;
    import swarm.neo.AddrPort;
    import ocean.io.device.File;
    import ocean.core.Buffer;
    import turtle.env.Shell;
    import Integer = ocean.text.convert.Integer_tango;

    /// Enum defining the possibles states of the fake node service.
    private enum State
    {
        Init,
        Running,
        Stopped
    }

    /// State of the fake node service.
    private State state;

    /// Used to prevent creating multiple fake nodes of the same type.
    static bool already_created = false;

    /// Node service object. Instantiated when start() is called.
    protected NodeType node;

    /***************************************************************************

        Constructor

    ***************************************************************************/

    public this ( )
    {
        if (already_created)
            assert(false, "Can only have one " ~ id ~ " per turtle test app");
        already_created = true;
    }

    /***************************************************************************

        Starts the fake node as part of test suite event loop. It will
        only terminate when whole test suite process dies.

        Params:
            addr = address to bind listening socket to
            port = port to bind listening socket to

    ***************************************************************************/

    public void start ( cstring addr = "127.0.0.1", ushort port = 0 )
    {
        assert(this.state == State.Init, "Node has already been started");

        this.node = this.createNode(NodeItem(addr.dup, port));
        this.state = State.Running;

        turtle_env_registry.register(this);
    }

    /***************************************************************************

        Restarts the fake node, reopening the listening socket on the same port
        determined in the initial call to start().

        Notes:
            1. Restarting the node *does not* clear any data in its storage
               engine. To do that, call reset().
            2. You must call stop() first, before calling restart().

    ***************************************************************************/

    public void restart ( )
    {
        assert(this.state == State.Stopped, "Node has not been stopped");

        this.node = this.createNode(this.node_item);
        this.state = State.Running;
    }

    /***************************************************************************

        Stops the fake node service. The node may be started again on the same
        port via restart().

    ***************************************************************************/

    final public void stop ( )
    {
        assert(this.state == State.Running, "Node is not running");

        this.stopImpl();
        this.state = State.Stopped;
    }

    /***************************************************************************

        Does hard reset of the node with terminating all persistent requests.
        Aliases to `clear` by default for backwards compatibility.

    ***************************************************************************/

    public void reset ( )
    {
        this.clear();
    }

    /***************************************************************************

        Generate nodes files for the fake nodes. If the node supports the neo
        protocol then the neo nodes will be written.

        Params:
            directory = The directory the files will be written to.

    ***************************************************************************/

    public void genConfigFiles ( cstring directory )
    {
        shell("mkdir -p " ~ directory);

        auto legacyfile = new File(directory ~ "/" ~ id ~ ".nodes",
            File.WriteCreate);
        scope (exit) legacyfile.close();

        legacyfile.write(this.node_item.Address ~ ":" ~
            Integer.toString(this.node_item.Port));

        static if ( is(typeof(this.node.neo_address)) )
        {
            auto neofile = new File(directory ~ "/" ~ id ~ ".neo.nodes",
                File.WriteCreate);
            scope (exit) neofile.close();

            neofile.write(this.node_item.Address ~ ":" ~
                Integer.toString(this.node.neo_address.port));
        }
    }

    /***************************************************************************

        ITurtleEnv interface method implementation. Should not be called
        manually.

        Uses turtle env addition registry to stop tracking errors after all
        tests have finished. This is necessary because applications don't do
        clean connection shutdown when terminating, resulting in socker errors
        being reported on node side.

    ***************************************************************************/

    public void unregister ( )
    {
        this.ignoreErrors();
    }

    /***************************************************************************

        Creates a fake node at the specified address/port.

        Params:
            node_item = address/port

    ***************************************************************************/

    abstract protected NodeType createNode ( NodeItem node_item );

    /***************************************************************************

        Returns:
            address/port on which node is listening

    ***************************************************************************/

    abstract public NodeItem node_item ( );

    /***************************************************************************

        Fake node service stop implementation.

    ***************************************************************************/

    abstract protected void stopImpl ( );

    /***************************************************************************

        Removes all data from the fake node service.

    ***************************************************************************/

    abstract public void clear ( );

    /***************************************************************************

        Suppresses log output from the fake node if used version of node proto
        supports it.

    ***************************************************************************/

    abstract public void ignoreErrors ( );
}
