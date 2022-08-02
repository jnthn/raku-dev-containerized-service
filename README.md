# Dev::ContainerizedService

This module aims to ease the process of setting up services (such as Postgres)
for the purpose of having a local development environment for Raku projects.
For example, one might have a Raku web application that uses a database. In
order to try out the application locally, a database instance needs to be set
up. Ideally this should be effortless and also isolated.

As the name suggests, this module achieves its aims using containers. It
depends on nothing more than Raku and having a functioning `docker`
installation.

## Usage

### Getting Started

Let's assume we have a web application that uses a Postgres database and expects
that the `DB_CONN_INFO` environment variable will be populated with a connection
string.

To make a development environment configuration using this module, we create a
script `devenv.raku`:

```raku
#!/usr/bin/env raku
use Dev::ContainerizedService;

service 'postgres', :tag<13.0>, -> (:$conninfo, *%) {
    env 'DB_CONN_INFO', $conninfo;
}
```

The `service` function specifies the service ID, a Docker image tag, and a block that
should be called when the service is up and running. The `env` function, located in a
service, specifies an environment variable to be set.

We can then (assuming `chmod +x devenv.raku`) use the script as follows:

```
./devenv.raku raku -Ilib service.raku 
```

This will:

1. Pull the Postgres docker container if required
2. Run the container, setting up a database user/password and binding it to a free
   port
3. Run `raku -Ilib service.raku` with the `DB_CONN_INFO` environment variable set

If using the `cro` development tool, one could do:

```
./devenv.raku cro run 
```

### Additional Actions

The service block is run after the container is started (service implementations
include readiness checks). As well as - or instead of - specifying environment
variables to pass to the process, one can write any Raku code there. For
example, one could run database migrations (in the case where it's desired to
have them explicitly applied to production, rather than having them applied at
application startup time).

### Is this magic?

Not really; the `Dev::ContainerizedService` module exports a `MAIN` sub, which is
how it gets to provide the program entrypoint.

## Available Services

### Postgres

Either obtain a connection string:

```raku
service 'postgres', :tag<13.0>, -> (:$conninfo, *%) {
    env 'DB_CONN_INFO', $conninfo;
}
```

Or the individual parts of the database connection details:

```raku
service 'postgres', :tag<13.0>, -> (:$host, :$port, :$user, :$password, :$dbname, *%) {
    env 'DB_HOST', $host;
    env 'DB_PORT', $port;
    env 'DB_USER', $user;
    env 'DB_PASS', $password;
    env 'DB_NAME', $dbname;
}
```

### Redis

Obtain the host and port of the started instance:

```raku
service 'redis', :tag<7.0>, -> (:$host, :$port) {
    env 'REDIS_HOST', $host;
    env 'REDIS_PORT', $port;
}
```

## The service I want isn't here!

1. Fork this repository.
2. Add a module `Dev::ContainerizedService::Spec::Foo`, and in it write a
   class of the same name that does `Dev::ContainerizedService::Spec`. See
   the role's documentation as well as other specs as an example.
3. Add a mapping to the `constant %specs` in `Dev::ContainerizedService`.
4. Write a test to make sure it works.
5. Add an example to the `README.md`.
6. Submit a pull request.
