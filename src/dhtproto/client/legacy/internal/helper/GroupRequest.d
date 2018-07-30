/*******************************************************************************

    Group request manager alias template.

    Usage example:

    ---

        import ocean.io.select.EpollSelectDispatcher;
        import dhtproto.client.DhtClient;
        import dhtproto.client.legacy.internal.helper.GroupRequest;

        // Initialise epoll, dht and connect to dht
        auto epoll = new EpollSelectDispatcher;
        auto dht = new DhtClient(epoll);
        dht.addNodes("dht.nodes");
        dht.nodeHandshake((DhtClient.RequestContext c, bool ok){}, null);
        epoll.eventLoop;

        // Request notifier
        void notifier ( DhtClient.RequestNotification info )
        {
            with ( typeof(info.type) ) switch ( info.type )
            {
                case Finished:
                    // GetAll on a single node finished
                break;

                case GroupFinished:
                    // GetAlls over all nodes finished
                break;

                default:
            }
        }

        // Set up group request (with imaginary get callback)
        auto request = dht.getAll("channel", &getCb, &notifier);
        auto get_all = new GroupRequest!(DhtClient.GetAll)(request);

        // Run group request
        dht.assign(get_all);
        epoll.eventLoop;

    ---

    Copyright:
        Copyright (c) 2012-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.helper.GroupRequest;



/*******************************************************************************

    Imports

*******************************************************************************/

import swarm.client.helper.GroupRequest;

import dhtproto.client.DhtClient;

import dhtproto.client.legacy.internal.request.notifier.RequestNotification;

import dhtproto.client.legacy.internal.request.params.RequestParams;



/*******************************************************************************

    Group request manager alias template.

    Template params:
        Request = type of request struct to manage (should be one of the structs
            returned by the dht client request methods)

*******************************************************************************/

public template GroupRequest ( Request )
{
    alias IGroupRequestTemplate!(Request, RequestParams, RequestNotification)
        GroupRequest;
}

