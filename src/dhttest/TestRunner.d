/*******************************************************************************
    
    Reusable test runner class for testing any DHT node implementation, based
    on turtle facilities. In most cases, simply providing DHT node binary name
    to runner constructor should be enough.

    Copyright:
        Copyright (c) 2015-2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.TestRunner;

/*******************************************************************************

    Imports

*******************************************************************************/

import ocean.transition;

import turtle.runner.Runner;

import dhttest.cases.Handshake;
import dhttest.cases.Basic;
import dhttest.cases.BasicListen;
import dhttest.cases.OrderedPut;
import dhttest.cases.UnorderedPut;
import dhttest.cases.OrderedRemove;
import dhttest.cases.UnorderedRemove;
import dhttest.cases.BatchListen;

import dhttest.cases.neo.Dummy;

/*******************************************************************************

    Test runner specialized for DHT nodes

*******************************************************************************/

class DhtTestRunner : TurtleRunnerTask!(TestedAppKind.Daemon)
{
    /***************************************************************************

        No additional configuration necessary, assume localhost and
        hard-coded port number (10000)
        
    ***************************************************************************/

    override public void prepare ( ) { }

    /***************************************************************************

        No arguments but add small startup delay to let DHT node initialize
        listening socket.

    ***************************************************************************/

    override protected void configureTestedApplication ( out double delay,
        out istring[] args, out istring[istring] env )
    {
        delay = 1.0;
        args  = null;
        env   = null;
    }
}
