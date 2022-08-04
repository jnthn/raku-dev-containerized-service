use v6.d;
use Dev::ContainerizedService::Spec;
use Dev::ContainerizedService::Tool;
use JSON::Fast;

# Mapping of service names to the module name to require and (matching) class to use.
my constant %specs =
        'postgres' => 'Dev::ContainerizedService::Spec::Postgres',
        'redis' => 'Dev::ContainerizedService::Spec::Redis';

#| Details of a specified service.
my class Service {
    has Str $.name is required;
    has Str $.service-id is required;
    has Str $.image is required;
    has Dev::ContainerizedService::Spec $.spec is required;
    has Promise $.pull-promise is required;
    has &.setup is required;
    has %.env;

    method run-setup(--> Nil) {
        my $*D-CS-SERVICE = self;
        &!setup($!spec.service-data);
    }

    method add-env(Str $name, Str $value --> Nil) {
        %!env{$name} = $value;
    }
}

# Declared project name, if any.
my Str $project;

# Declared default storage key, if any.
my Str $default-store;

# Declared services.
my Service @services;

#| Declare a project name for the development configuration. This is required if
#| wanting to have persistent storage of the created services between runs.
sub project(Str $name --> Nil) is export {
    with $project {
        note "Already called `project` function; it can only be used once";
        exit 1;
    }
    else {
        $project = $name;
    }
}

#| Declare that we should store the service state that is produced (for example, by
#| having the data be on a persistent docker). Optionally provide a name for the
#| default store.
sub store(Str $name = 'default' --> Nil) is export {
    without $project {
        note "Must call the `project` function before using `store`";
        exit 1;
    }
    with $default-store {
        note "Already called `store` function; it can only be used once";
        exit 1;
    }
    else {
        $default-store = $name;
    }
}

#| Declare that a given development service is needed. The body block is run once the
#| service has been started, and can do any desired setup work or specify environment
#| variables to pass to the process that is run. A tag (for the container of the
#| service) can be specified, and the service can be given an explicit name (only
#| really important if one wishes to bring up, for example, two different Postgres
#| instances and have a clear way to refer to each one).
sub service(Str $service-id, &setup, Str :$tag, Str :$name, *%options) is export {
    # Resolve the service spec.
    my $spec-class = get-spec($service-id);

    # Figure out a name.
    my $base-name = $name // $service-id;
    my $chosen-name = $base-name;
    my $idx = 2;
    while @services.first(*.name eq $chosen-name) {
        $chosen-name = $base-name ~ '-' ~ $idx++;
    }

    # Instantiate the container specification.
    my Dev::ContainerizedService::Spec $spec = $spec-class.new(|%options);

    # Start pulling the container.
    my $image = $spec.docker-container ~ ":" ~ ($tag // $spec.default-docker-tag);
    my $pull-promise = start sink docker-pull-image($image);

    # Add service info to collected services.
    push @services, Service.new(:name($chosen-name), :$service-id, :$image, :$spec, :$pull-promise, :&setup);
}

#| Declare an environment variable be supplied to the process that is started.
sub env(Str $name, Str() $value --> Nil) is export {
    with $*D-CS-SERVICE {
        .add-env($name, $value);
    }
    else {
        die "Can only use 'env' in the scope of a 'service' block";
    }
}

#| Run a command in the containerized development environment.
multi sub MAIN('run', Str :$store = $default-store, *@command) is export {
    # Make sure we've completed pulling all services; if we have any errors, stop.
    await Promise.allof(@services.map(*.pull-promise));
    with @services.first(*.pull-promise.status == Broken) {
        note "Failed to pull container for service '{.service-id}':\n{.pull-promise.cause.message.indent(4)}";
        exit 1;
    }

    # If we have storage, then set the storage prefix and load any persisted settings.
    if $store {
        for @services -> Service $service {
            $service.spec.store-prefix = store-prefix($store, $service.name);
            my $settings-file = settings-file($store, $service.name());
            if $settings-file.e {
                $service.spec.load(from-json $settings-file.slurp);
            }
        }
    }

    react {
        # We'll keep track of running container processes.
        my class Container {
            has Str $.name is required;
            has Promise $.started is required;
            has Proc::Async $.container-process is required;
        }
        my Container @containers;

        # Start the container for each service.
        for @services.kv -> $idx, Service $service {
            my $name = "dev-service-$*PID-$idx";
            my $container-process = Proc::Async.new: 'docker', 'run', '-t', '--rm',
                    $service.spec.docker-options, '--name', $name, $service.image,
                    $service.spec.docker-command-and-arguments;
            my $started = Promise.new;
            @containers.push((Container.new(:$name, :$service, :$started, :$container-process)));
            whenever $container-process.ready {
                # If the container can't be started, give up with an error.
                QUIT {
                    default {
                        note "Failed to start '$service.service-id()': { .message }";
                        stop-services();
                        exit 1;
                    }
                }

                # Otherwise, wait for the service to be determined ready.
                whenever $service.spec.ready(:$name) {
                    $service.run-setup();
                    if $store {
                        my $settings-file = settings-file($store, $service.name);
                        $settings-file.spurt: to-json $service.spec.save;
                    }
                    $started.keep;
                    CATCH {
                        default {
                            note "An exception occurred in the service block for '$service.service-id()':\n{.gist.indent(4)}";
                            stop-services();
                            exit 1;
                        }
                    }
                }
            }
            $container-process.start;
        }

        # When containers are all started.
        whenever Promise.allof(@containers.map(*.started)) {
            # Form the environment.
            my %ENV = %*ENV;
            for flat @services.map(*.env.kv) -> $name, $value {
                %ENV{$name} = $value;
            }

            # Arguments given to us include the program name to run. Thus feed them directly into the
            # Proc::Async constructor, which uses the first as the program name.
            my $proc = Proc::Async.new(@command);
            whenever $proc.start(:%ENV) {
                stop-services();
                exit .exitcode;
            }
        }

        sub stop-services(--> Nil) {
            for @containers {
                .container-process.kill;
                try docker-stop .name;
            }
        }
    }
}

#| List stores for the project specified by this development environment script.
multi sub MAIN('stores') is export {
    ensure-stores-available();
    .say for project-dir().dir.grep(*.d).map(*.basename).sort;
}

#| Display the service data of the currently running or most recently run services,
#| optionally specifying the store name.
multi sub MAIN('show', Str :$store = $default-store) is export {
    ensure-stores-available();
    for @services -> Service $service {
        say $service.name;
        my $settings-file = settings-file($store, $service.name);
        if $settings-file.e {
            $service.spec.store-prefix = store-prefix($store, $service.name);
            $service.spec.load(from-json $settings-file.slurp);
            for $service.spec.service-data.sort(*.key) {
                say "  {.key}: {.value}";
            }
        }
        else {
            say "  Not run";
        }
    }
}

#| Run a tool for a service.
multi sub MAIN('tool', Str $service-name, Str $tool-name, *@extra-args, Str :$store = $default-store) {
    ensure-stores-available();
    with @services.first(*.name eq $service-name) -> Service $service {
        my $tool = $service.spec.tools.first(*.name eq $tool-name);
        if $tool ~~ Dev::ContainerizedService::Tool {
            my $settings-file = settings-file($store, $service.name);
            if $settings-file.e {
                $service.spec.store-prefix = store-prefix($store, $service.name);
                $service.spec.load(from-json $settings-file.slurp);
                my $tool-instance = $tool.new:
                        image => $service.image,
                        store-prefix => $service.spec.store-prefix,
                        service-data => $service.spec.service-data;
                $tool-instance.run(@extra-args);
            }
            else {
                note "Service '$service-name' has not yet been run for store '$store'; tools unavailable";
            }
        }
        elsif $service.spec.tools -> @tools {
            note "No such tool '$tool-name'; available: @tools.map(*.name).join(', ')";
            exit 1;
        }
        else {
            note "There are no tools available for $service-name";
            exit 1;
        }
    }
    else {
        note "No such service '$service-name'; available: @services.map(*.name).join(', ')";
        exit 1;
    }
}

#| Delete a store for this development environment script.
multi sub MAIN('delete', Str :$store = $default-store) {
    ensure-stores-available();
    for @services -> Service $service {
        my $settings-file = settings-file($store, $service.name);
        if $settings-file.e {
            $service.spec.store-prefix = store-prefix($store, $service.name);
            $service.spec.load(from-json $settings-file.slurp);
            $service.spec.cleanup();
            $settings-file.unlink;
        }
    }
}

sub ensure-stores-available(--> Nil) {
    without $project {
        note "This development environment script does not call `project`, so cannot use stores";
        exit 1;
    }
    without $default-store {
        note "This development environment script does not call `store`, so cannot use stores";
        exit 1;
    }
}

sub project-dir(--> IO::Path) {
    my $dir = $*HOME.add('.raku-dev-cs').add($project);
    $dir.mkdir unless $dir.d;
    return $dir
}

sub store-dir(Str $store --> IO::Path) {
    my $dir = project-dir.add($store);
    $dir.mkdir unless $dir.d;
    return $dir;
}

sub settings-file(Str $store, Str $service --> IO::Path) {
    store-dir($store).add($service)
}

sub store-prefix(Str $store, Str $service-name --> Str) {
    "$project-$store-$service-name-"
}

#| Look up the specification for a service of the given ID. Dies if it cannot be
#| found. Exported for modules building upon this one.
sub get-spec(Str $service-id --> Dev::ContainerizedService::Spec) is export(:get-spec) {
    with %specs{$service-id} -> $module {
        # Load the specification module.
        require ::($module);
        return ::($module);
    }
    else {
        die "No service specification for '$service-id'; available are: " ~
                %specs.keys.sort.join(", ")
    }
}

#| Tries to pull a docker image. Fails if it cannot. Exported for modules building upon
#| this one.
sub docker-pull-image(Str $image) is export(:docker) {
    my Str $error = '';
    react {
        my $proc = Proc::Async.new('docker', 'pull', $image);
        whenever $proc.stdout {}
        whenever $proc.stderr {
            $error ~= $_;
        }
        whenever $proc.start -> $result {
            if $result.exitcode != 0 {
                $error = "Exit code $result.exitcode()\n$error";
            }
            else {
                $error = Nil;
            }
        }
    }
    $error ?? fail($error) !! Nil
}

#| Sends the stop command to a docker container. Exported for modules building upon this one.
sub docker-stop(Str $name --> Nil) is export(:docker) {
    my $proc = Proc::Async.new('docker', 'stop', $name);
    .tap for $proc.stdout, $proc.stderr;
    try sink await $proc.start;
}
