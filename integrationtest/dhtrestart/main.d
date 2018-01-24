/*******************************************************************************

    Test dht node restart functionality in combination with external dht client
    doing `Listen` request. Uses `dhtapp` as a tested application which will
    start listening on "test_channel1" and push all records to "test_channel2".

    Copyright:
        Copyright (c) 2017 sociomantic labs GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module integrationtest.dhtrestart.main;

import ocean.transition;

import turtle.runner.Runner;
import turtle.TestCase;

/// ditto
class DhtRestartTests : TurtleRunnerTask!(TestedAppKind.Daemon)
{
    import turtle.env.Dht;

    override protected void configureTestedApplication ( out double delay,
        out istring[] args, out istring[istring] env )
    {
        delay = 0.1;
    }

    override public void prepare ( )
    {
        Dht.initialize();
        dht.start("127.0.0.1", 0);
        dht.genConfigFiles(this.context.paths.sandbox ~ "/etc");
    }

    override public void reset ( )
    {
        dht.clear();
    }
}

version ( UnitTest ) { }
else
int main ( istring[] args )
{
    auto runner = new TurtleRunner!(DhtRestartTests)("dhtapp", "",
        "dhtrestart");
    return runner.main(args);
}

/*******************************************************************************

    Verifies scenario where test cases pushes records to a channel tested app
    listens on, both before and after fake node restart.

*******************************************************************************/

class RestartWithListeners : TestCase
{
    import turtle.env.Dht;

    import ocean.core.Test;
    import ocean.task.util.Timer;

    override void run ( )
    {
        dht.put("test_channel1", 0xABCD, "value");
        wait(100_000); // small delay to ensure fakedht manages to process
                       // `Put` request to "test_channel2"

        dht.stop();
        dht.restart();
        wait(300_000); // small delay to ensure tested app reassigns Listen

        dht.put("test_channel1", 0xABCD, "value2");
        wait(100_000); // small delay to ensure fakedht manages to process
                       // `Put` request to "test_channel2"
        test!("==")(dht.get!(cstring)("test_channel2", 0xABCD), "value2");
    }
}
