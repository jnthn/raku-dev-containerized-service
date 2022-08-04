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
./devenv.raku run raku -Ilib service.raku
```

This will:

1. Pull the Postgres docker container if required
2. Run the container, setting up a database user/password and binding it to a free
   port
3. Run `raku -Ilib service.raku` with the `DB_CONN_INFO` environment variable set

If using the `cro` development tool, one could do:

```
./devenv.raku run cro run
```

### Additional Actions

The service block is run after the container is started (service implementations
include readiness checks). As well as - or instead of - specifying environment
variables to pass to the process, one can write any Raku code there. For
example, one could run database migrations (in the case where it's desired to
have them explicitly applied to production, rather than having them applied at
application startup time).

### Retaining data

By default, any created databases are not persisted once the `run` command is
completed. To change this, alter the configuration file to specify a project name
(the name of your application) and call `store`:

```raku
#!/usr/bin/env raku
use Dev::ContainerizedService;

project 'my-app';
store;

service 'postgres', :tag<13.0>, -> (:$conninfo, *%) {
    env 'DB_CONN_INFO', $conninfo;
}
```

Now when using `./devenv.raku run ...`, for services that support it, Docker
volume(s) will be created and the generated password(s) for services will be
saved (in your home directory). These will be reused on subsequent runs.

To clean up this storage, use:

```raku
./devenv.raku delete
```

Which will remove any created volumes along with saved settings.

### Showing produced configuration

When using storage, it is also possible to see the most recently passed service
settings for each service by using:

```raku
./devenv.raku show
```

The output looks like this:

```raku
postgres
  conninfo: host=localhost port=29249 user=test password=xxlkC2MrOv4yJ3vP1V-pVI7 dbname=test
  dbname: test
  host: localhost
  password: xxlkC2MrOv4yJ3vP1V-pVI7
  port: 29249
  user: test
```

When used while `run` is active, this is handy for obtaining connection string
information in order to connect to the database using tools of your choice.

### Multiple stores

Calling:

```raku
store;
```

Is equivalent to calling:

```raku
store 'default';
```

That is, it specifies the name of a default store. It is possible to have multiple
independent stores instead, by using the `--store` argument before the `run`
subcommand:

```raku
./devenv.raku --store=bug42 run cro run
```

To see the created stores, use:

```raku
./devenv.raku stores
```

To show the produced service configuration for a particular store, use:

```raku
./devenv.raku --store=bug42 show
```

To delete a particular store, rather than the default one, use:

```raku
./devenv.raku --store=bug42 delete
```

### Multiple instances of a given service

One can have multiple instances of a given service. When doing this, it is wise
to assign them names (otherwise names like `postgres-2` will be generated, and
this will not be too informative in `show` output):

```raku
service 'postgres', :tag<13.0>, :name<pg-products> -> (:$conninfo, *%) {
    env 'PRODUCT_DB_CONN_INFO', $conninfo;
}

service 'postgres', :tag<13.0>, :name<pg-billing> -> (:$conninfo, *%) {
    env 'BILLING_DB_CONN_INFO', $conninfo;
}
```

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

Postgres supports storage of the database between runs when `store` is used.

### Redis

Obtain the host and port of the started instance:

```raku
service 'redis', :tag<7.0>, -> (:$host, :$port) {
    env 'REDIS_HOST', $host;
    env 'REDIS_PORT', $port;
}
```

Redis is currently always in-memory and will never be stored.

## The service I want isn't here!

1. Fork this repository.
2. Add a module `Dev::ContainerizedService::Spec::Foo`, and in it write a
   class of the same name that does `Dev::ContainerizedService::Spec`. See
   the role's documentation as well as other specs as an example.
3. Add a mapping to the `constant %specs` in `Dev::ContainerizedService`.
4. Write a test to make sure it works.
5. Add an example to the `README.md`.
6. Submit a pull request.
