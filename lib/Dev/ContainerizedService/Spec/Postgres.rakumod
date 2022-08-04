use v6.d;
use Dev::ContainerizedService::Spec;

#| Development service specification for Postgres.
class Dev::ContainerizedService::Spec::Postgres does Dev::ContainerizedService::Spec {
    has Int $!port;
    has Str $!password;

    method docker-container(--> Str) { 'postgres' }

    method default-docker-tag(--> Str) { 'latest' }

    method save(--> Map) { { :$!password, :$!port } }

    method load(%saved --> Nil) {
        $!port = $_ with %saved<port>;
        $!password = $_ with %saved<password>;
    }

    method cleanup(--> Nil) {
        self.delete-volume("{$!store-prefix}data")
    }

    method docker-options(--> Positional) {
        # Re-use password over runs, but produce a new port.
        $!password //= self.generate-secret;
        $!port = self.generate-port;
        [
            '-e', "POSTGRES_PASSWORD=$!password",
            '-e', 'POSTGRES_USER=test',
            '-e', 'POSTGRES_DB=test',
            '-p', "$!port:5432",
            |($!store-prefix ?? ('--mount', "type=volume,src={$!store-prefix}data,dst=/var/lib/postgresql/data") !! ())
        ]
    }

    method ready(Str :$name --> Promise) {
        start {
            # We use pg_isready, but that still sometimes gives us an indication
            # that it is ready a little earlier than we can really connect to it,
            # so look for some consecutive positive responses.
            my $cumulative-ready = 0;
            for ^60 {
                my $proc = Proc::Async.new('docker', 'exec', $name, 'pg_isready',
                        '-U', 'test');
                .tap for $proc.stdout, $proc.stderr;
                my $outcome = try await $proc.start;
                if ($outcome.?exitcode // -1) == 0 {
                    $cumulative-ready++;
                    last if $cumulative-ready > 2;
                }
                else {
                    $cumulative-ready = 0;
                }
                await Promise.in(1.0);
            }
        }
    }

    method service-data(--> Associative) {
        {
            :host<localhost>, :$!port, :user<test>, :$!password, :dbname<test>,
            :conninfo("host=localhost port=$!port user=test password=$!password dbname=test")
        }
    }
}
