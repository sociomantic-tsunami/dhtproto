/*******************************************************************************

    Mixins for request setup structs used in DhtClient.

    Copyright:
        Copyright (c) 2011-2017 dunnhumby Germany GmbH. All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE.txt for details.

*******************************************************************************/

module dhtproto.client.legacy.internal.RequestSetup;



/*******************************************************************************

    Imports

    Note that swarm.client.RequestSetup is imported publicly, as all of the
    templates it contains are needed wherever this module is imported.

*******************************************************************************/

public import swarm.client.RequestSetup;

/*******************************************************************************

    Mixin for the methods use by dht client requests which have an I/O delegate.

*******************************************************************************/

public template IODelegate ( )
{
    import ocean.meta.types.Qualifiers;
    import ocean.core.TypeConvert : downcast;
    import ocean.core.Verify;

    alias typeof(this) This;
    static assert (is(This == struct));

    /***************************************************************************

        I/O delegate

    ***************************************************************************/

    private RequestParams.IOItemUnion io_item;


    /***************************************************************************

        Sets the I/O delegate for a request.

        Params:
            io = I/O delegate

        Returns:
            this pointer for method chaining

    ***************************************************************************/

    public This* io ( T ) ( T io )
    {
        this.io_item = this.io_item(io);
        return &this;
    }


    /***************************************************************************

        Copies the value of the io_item member into the provided
        request params class instance.

        Params:
            params = IRequestParams instance to write into

    ***************************************************************************/

    private void setup_io_item ( IRequestParams params )
    {
        auto params_ = downcast!(RequestParams)(params);
        verify(params_ !is null);

        params_.io_item = this.io_item;
    }
}


/*******************************************************************************

    Mixin for the methods used by dht client requests which pass a filter string
    to the node.

*******************************************************************************/

public template Filter ( )
{
    import ocean.meta.types.Qualifiers;
    import ocean.core.TypeConvert : downcast;
    import ocean.core.Verify;

    alias typeof(this) This;
    static assert (is(This == struct));

    /***************************************************************************

        Request filter string.

    ***************************************************************************/

    private cstring filter_string;


    /***************************************************************************

        Sets the filter string for a request.

        Params:
            filter = filter string

        Returns:
            this pointer for method chaining

    ***************************************************************************/

    public This* filter ( cstring filter )
    {
        this.filter_string = filter;

        // TODO: this block of code which switches the command type internally
        // should be removed if we want to modify the GetAll / GetRange protocol
        // to make filtering a true built-in option.
        with ( DhtConst.Command.E ) switch ( this.command_code )
        {
            case GetAll:
            case GetAllFilter:
                this.command_code = filter.length > 0 ? GetAllFilter : GetAll;
                break;
            default:
                assert(false, "filter method called on command which doesn't support filtering!");
        }

        return &this;
    }


    /***************************************************************************

        Copies the value of the filter_string member into the provided request
        params class instance.

        Params:
            params = IRequestParams instance to write into

    ***************************************************************************/

    private void setup_filter_string ( IRequestParams params )
    {
        auto params_ = downcast!(RequestParams)(params);
        verify(params_ !is null);

        params_.filter = this.filter_string;
    }
}


/*******************************************************************************

    Mixin for the methods used by dht client requests which operate with a key.

*******************************************************************************/

public template Key ( )
{
    import ocean.meta.types.Qualifiers;
    import ocean.core.TypeConvert : downcast;
    import ocean.core.Verify;
    static import swarm.util.Hash;

    alias typeof(this) This;
    static assert (is(This == struct));

    /***************************************************************************

        Request hash.

    ***************************************************************************/

    private hash_t hash;


    /***************************************************************************

        Sets the key for a request.

        Template params:
            Key = type of key

        Params:
            key = request key

        Returns:
            this pointer for method chaining

    ***************************************************************************/

    public This* key ( Key ) ( Key key )
    {
        version (X86_64) static assert(!is( Key == uint),
            "Please use hash_t instead of uint.");

        this.hash = swarm.util.Hash.toHash(key);

        return &this;
    }


    /***************************************************************************

        Sets the context for a request to the key hash.

        Returns:
            this pointer for method chaining

    ***************************************************************************/

    public This* contextFromKey ( )
    {
        this.user_context = RequestContext(this.hash);

        return &this;
    }


    /***************************************************************************

        Copies the value of the hash member into the provided request params
        class instance.

        Params:
            params = IRequestParams instance to write into

    ***************************************************************************/

    private void setup_hash ( IRequestParams params )
    {
        auto params_ = downcast!(RequestParams)(params);
        verify(params_ !is null);

        params_.hash = this.hash;
    }
}
