use v6.d;

#| Specification of a containerized service. This role is done by each service
#| that we want to provide a container for. Classes implementing this role
#| should add further public attributes for user-configurable options, and can
#| use private ones for state produced when working out the container options
#| (for example, generated ports or throw-away passwords) that should be used
#| later when producing the service options.
role Dev::ContainerizedService::Spec {
    #| A store prefix. Set before docker-options is called in the event that the
    #| container's state should be stored. If not set, then it should be assumed
    #| that a throwaway container is needed. Should be used as part of a volume
    #| name in order to make the service state persistent.
    has Str $.store-prefix is rw;

    #| Specify the docker container name.
    method docker-container(--> Str) { ... }

    #| The default docker tag.
    method default-docker-tag(--> Str) { ... }

    #| Save details of the container specification that should persist in a
    #| stored configuration. Typically this will be a generated password and,
    #| potentially, a selected port number; a common pattern is to pick a new
    #| port number each run (that is, in docker-options), and to save it for
    #| being able to dump or use if running tools. Must return a hash that
    #| can be serialized by JSON::Fast. Called after the service has been
    #| successfully launched and deemed ready.
    method save(--> Map) { {} }

    #| Load saved configuration. Called before docker-options.
    method load(%saved --> Nil) { }

    #| Clean up any persistent storage, such as docker volumnes.
    method cleanup(--> Nil) { }

    #| Options to pass to `docker`.
    method docker-options(--> Positional) { [] }

    #| Command and argument to pass to `docker`.
    method docker-command-and-arguments(--> Positional) { [] }

    #| Returns a Promise that will be kept when the service is ready, or
    #| broken if it cannot be determined ready. The container name is
    #| passed in.
    method ready(Str :$name --> Promise) { return Promise.kept(True) }

    #| Gets a hash of information about the started service (for example,
    #| connection information).
    method service-data(--> Associative) { ... }

    #| Get an list of tools, which should be provided as type objects of
    #| classes doing the role Dev::ContainerizedService::Tool.
    method tools(--> List) {
        Empty
    }

    #| The first time this is called with a particular key, it generates a
    #| port number, picking one that is currently free. (This is inherently
    #| a bit racy, and some mitigations are done to try and avoid conflicts
    #| in parallel tests or parallel starting of services for development.)
    method generate-port(--> Int) {
        for ^100 {
            # Pick a random port between 26000 and 30000, to reduce the
            # risk of collisions.
            my $candidate = 26000 + (^4000).pick;
            my $try-conn = IO::Socket::Async.connect('localhost', $candidate);
            await Promise.anyof($try-conn, Promise.in(1.0));
            if $try-conn.status == Kept {
                # We could connect, so not free.
                $try-conn.result.close;
            }
            else {
                # Could not connect, so may well be free.
                return $candidate;
            }
        }
        die "Could not find a free port in 100 attempts";
    }

    #| Generates a random secret, which could be used as a password for the
    #| service instance.
    method generate-secret(--> Str) {
        my constant @chars = flat 'A'..'Z', 'a'..'z', '1'..'9', <_ ->;
        @chars.roll((15..25).pick).join
    }

    #| A common way to implement the ready method is to check if a connection
    #| can be made to a certain host/port. This method factors it out for
    #| reuse by various specifications that wish to do that.
    method ready-by-connectability(Str $host, Int $port --> Promise) {
        start {
            # Wait until we can connect.
            for ^60 {
                my $conn = IO::Socket::Async.connect($host, $port);
                my $delay = Promise.in(1);
                await Promise.anyof($conn, $delay;);
                if $conn.status == Kept {
                    $conn.result.close;
                    last;
                }
                await $delay;
            }
        }
    }

    #| Deletes the specified Docker volume, if it exists.
    method delete-volume(Str $volume --> Nil) {
        react {
            my $proc = Proc::Async.new('docker', 'volume', 'rm', $volume);
            $proc.stdout.tap;
            $proc.stderr.tap;
            whenever $proc.start {
                done;
            }
        }
    }
}
