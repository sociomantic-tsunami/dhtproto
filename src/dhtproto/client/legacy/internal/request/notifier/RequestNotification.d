/*******************************************************************************

    Dht client request notifier

    Copyright:
        Copyright (c) 2010-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.request.notifier.RequestNotification;



/*******************************************************************************

    Imports

*******************************************************************************/

import swarm.client.request.notifier.IRequestNotification;

import swarm.Const;

import dhtproto.client.legacy.DhtConst;

import ocean.core.Verify;



/*******************************************************************************

    Request notification

*******************************************************************************/

public class RequestNotification : IRequestNotification
{
    /***************************************************************************

        Constructor.

        Params:
            command = command of request to notify about
            context = context of request to notify about

    ***************************************************************************/

    public this ( ICommandCodes.Value command, Context context )
    {
        verify((command in DhtConst.Command()) !is null);

        super(DhtConst.Command(), DhtConst.Status(), command, context);
    }
}

