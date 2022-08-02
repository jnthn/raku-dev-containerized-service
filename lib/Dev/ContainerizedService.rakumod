use v6.d;
use Dev::ContainerizedService::Spec;

# Mapping of service names to the module name to require and (matching) class to use.
my constant %specs =
        'postgres' => 'Dev::ContainerizedService::Spec::Postgres',
        'redis' => 'Dev::ContainerizedService::Spec::Redis';

#| Details of a specified service.
my class Service {
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

# Declared services.
my Service @services;

#| Declare that a given development service is needed. The body block is run once the
#| service has been started, and can do any desired setup work. It can also specify
#| environment variables that will be passed to the process being launched under the
#| development service.
sub service(Str $service-id, &setup, Str :$tag, *%options) is export {
    # Resolve the service spec and instantiate.
    my $spec-class = get-spec($service-id);
    my Dev::ContainerizedService::Spec $spec = $spec-class.new(|%options);

    # Start pulling the container.
    my $image = $spec.docker-container ~ ":" ~ ($tag // $spec.default-docker-tag);
    my $pull-promise = start sink docker-pull-image($image);

    # Add service info to collected services.
    push @services, Service.new(:$service-id, :$image, :$spec, :$pull-promise, :&setup);
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

#| Exported entrypoint used in order to run the specified script with the setup work performed.
multi sub MAIN(|) is export {
    # Make sure we've completed pulling all services; if we have any errors, stop.
    await Promise.allof(@services.map(*.pull-promise));
    with @services.first(*.pull-promise.status == Broken) {
        note "Failed to pull container for service '{.service-id}':\n{.pull-promise.cause.message.indent(4)}";
        exit 1;
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
            my $proc = Proc::Async.new(@*ARGS);
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
