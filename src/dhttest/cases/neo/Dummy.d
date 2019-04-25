/*******************************************************************************

    Dummy neo test case so that the test runner has at least one test case to
    run.

    Otherwise, the test runner exits with a failure. When real neo test are
    added, this dummy test case can be removed.

    Copyright:
        Copyright (c) 2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhttest.cases.neo.Dummy;

import ocean.transition;

import dhttest.DhtTestCase;

/// ditto
class Dummy : DhtTestCase
{
    override public Description description ( )
    {
        Description desc;
        desc.name = "Dummy test case";
        return desc;
    }

    public override void run ( )
    {
    }
}
