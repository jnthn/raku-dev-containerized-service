use v6.d;

#| Implements launching a tool associated with a service. For example, for
#| Postgres the psql client could be launched.
role Dev::ContainerizedService::Tool {
    #| The image of the container being used.
    has Str $.image is required;

    #| The service data, which includes information that can be needed to
    #| connect to a service.
    has %.service-data is required;

    #| The store prefix, if any.
    has Str $.store-prefix is required;

    #| Returns the name of the tool. Must be callable on the type object.
    method name(--> Str) { ... }

    # Runs the tool. Any arguments passed after the tool name will be provided.
    method run(@extra-args --> Nil) { ... }
}
