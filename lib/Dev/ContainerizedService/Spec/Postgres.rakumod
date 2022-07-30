use v6.d;
use Dev::ContainerizedService::Spec;

#| Development service specification for Postgres.
class Dev::ContainerizedService::Spec::Postgres does Dev::ContainerizedService::Spec {
    has Int $!port = self.generate-port;
    has Str $!password = self.generate-secret;

    method docker-container(--> Str) { 'postgres' }

    method default-docker-tag(--> Str) { 'latest' }

    method docker-options(--> Positional) {
        [
            '-e', "POSTGRES_PASSWORD=$!password",
            '-e', 'POSTGRES_USER=test',
            '-e', 'POSTGRES_DB=test',
            '-p', "$!port:5432"
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
