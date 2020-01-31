/*******************************************************************************

    Runs dhttest on a fake DHT node instance.

    Copyright:
        Copyright (c) 2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module integrationtest.fakedht.main;

import turtle.runner.Runner;
import dhttest.TestRunner;
import ocean.meta.types.Qualifiers;

version ( unittest ) { }
else
int main ( istring[] args )
{
    auto runner = new TurtleRunner!(DhtTestRunner)("fakedht", "dhttest.cases.neo");
    return runner.main(args);
}
