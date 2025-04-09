use v6.d;

use Dev::ContainerizedService::Spec;

my constant $CONFIG = q:to/CONFIG/;
    <clickhouse>
        <logger>
            <console>1</console>
            <level>error</level>
        </logger>

        <asynchronous_metric_log remove="1"/>
        <backup_log remove="1"/>
        <error_log remove="1"/>
        <metric_log remove="1"/>
        <query_thread_log remove="1" />  
        <query_log remove="1" />
        <query_views_log remove="1" />
        <part_log remove="1"/>
        <session_log remove="1"/>
        <text_log remove="1" />
        <trace_log remove="1"/>
        <crash_log remove="1"/>
        <opentelemetry_span_log remove="1"/>
        <zookeeper_log remove="1"/>
        <processors_profile_log remove="1"/>
    </clickhouse>
    CONFIG

class Dev::ContainerizedService::Spec::ClickHouse does Dev::ContainerizedService::Spec {
    has Int $!port;
    has Str $!password;

    method docker-container(--> Str) {
        'clickhouse/clickhouse-server'
    }

    method default-docker-tag(--> Str) {
        'latest'
    }

    method save(--> Map) {
        { :$!password, :$!port }
    }

    method load(%saved --> Nil) {
        $!port = $_ with %saved<port>;
        $!password = $_ with %saved<password>;
    }

    method cleanup(--> Nil) {
        self.delete-volume("{ $!store-prefix }data")
    }

    method docker-options(--> Positional) {
        # Ensure we have configuration that quietens noisy output to only
        # errors written to a file.
        my $config-path = $*SPEC.tmpdir.add('dev-containerized-clickhouse-config.xml');
        spurt $config-path, $CONFIG;

        # Re-use password over runs, but produce a new port.
        $!password //= self.generate-secret;
        $!port = self.generate-port;
        [
            '-e', 'CLICKHOUSE_USER=test',
            '-e', 'CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=1',
            '-e', "CLICKHOUSE_PASSWORD=$!password",
            '-p', "$!port:8123",
            '--ulimit', 'nofile=262144:262144',
            '-v', "{$config-path.Str}:/etc/clickhouse-server/config.d/logging.xml",
            |($!store-prefix ?? ('--mount', "type=volume,src={ $!store-prefix }data,dst=/var/lib/clickhouse") !! ())
        ]
    }

    method ready(--> Promise) {
        start {
            # Since it starts, sets up, then restarts, we need to make sure it's really ready.
            my $cumulative-ready = 0;
            for ^60 {
                my $conn = await IO::Socket::Async.connect('localhost', $!port);
                $conn.close;
                $cumulative-ready++;
                if $cumulative-ready > 5 {
                    last;
                }
                else {
                    sleep 0.5;
                }
                CATCH {
                    default {
                        # Could not connect, so retry
                        $cumulative-ready = 0;
                        sleep 0.5;
                    }
                }
            }
        }
    }

    method service-data(--> Associative) {
        {
            :host<localhost>, :$!port, :user<test>, :$!password,
            :url("http://test:{ $!password }@localhost:{$!port}/")
        }
    }
}
