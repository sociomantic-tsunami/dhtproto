/*******************************************************************************

    Example main file running fake DHT node. Can be used to debug the
    protocol changes manually (in a more controlled environment).

    Copyright:
        Copyright (c) 2015-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module fakedht.main;

/*******************************************************************************

    Imports

*******************************************************************************/

import fakedht.DhtNode;

import dhtproto.client.legacy.DhtConst;

import ocean.io.select.EpollSelectDispatcher;
import ocean.io.select.client.TimerEvent;
import ocean.core.MessageFiber;
import ocean.task.Scheduler;

import ocean.util.log.Logger;
import ocean.util.log.AppendConsole;

/*******************************************************************************

    Configure logging

*******************************************************************************/

static this ( )
{
    Log.root.add(new AppendConsole);
    Log.root.level(Level.Info, true);
}

/*******************************************************************************

    Simple app that starts fake DHT and keeps it running until killed

*******************************************************************************/

version ( UnitTest ) { }
else
void main ( )
{
    SchedulerConfiguration config;
    initScheduler(config);

    auto node = new DhtNode(DhtConst.NodeItem("127.0.0.1".dup, 10000),
        theScheduler.epoll);

    auto log = Log.lookup("fakedht.main");
    log.info("Registering fake node");
    node.register(theScheduler.epoll);

    log.info("Starting infinite event loop, kill the process if not needed anymore");
    theScheduler.epoll.eventLoop();
}
