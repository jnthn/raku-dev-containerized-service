use v6.d;
use Test;

try require ::('Cro::HTTP::Client');
my $http-client = ::('Cro::HTTP::Client');
if $http-client ~~ Failure {
    skip 'No Cro::HTTP::Client available for testing';
}
else {
    my $test-dev-script = $*PROGRAM.parent.add('test-data/dev-clickhouse.raku');
    my @args = $*EXECUTABLE, '-I.', $test-dev-script, 'run', $*EXECUTABLE, '-e', q:to/RAKU/;
        use Cro::HTTP::Client;
        say 'TEST RESULT: Started';
        say %*ENV<CLICKHOUSE_HOST>:exists
            ?? 'TEST RESULT: Has environment CLICKHOUSE_HOST'
            !! 'TEST RESULT: Missing environment CLICKHOUSE_HOST';
        say %*ENV<CLICKHOUSE_PORT>:exists
            ?? 'TEST RESULT: Has environment CLICKHOUSE_PORT'
            !! 'TEST RESULT: Missing environment CLICKHOUSE_PORT';
        say %*ENV<CLICKHOUSE_USER>:exists
            ?? 'TEST RESULT: Has environment CLICKHOUSE_USER'
            !! 'TEST RESULT: Missing environment CLICKHOUSE_USER';
        say %*ENV<CLICKHOUSE_PASSWORD>:exists
            ?? 'TEST RESULT: Has environment CLICKHOUSE_PASSWORD'
            !! 'TEST RESULT: Missing environment CLICKHOUSE_PASSWORD';
        sleep 1;
        say "TEST RESULT: SELECTED " ~ await Cro::HTTP::Client.get-body("http://%*ENV<CLICKHOUSE_HOST>:%*ENV<CLICKHOUSE_PORT>/?query=SELECT%2042",
            auth => {
                username => %*ENV<CLICKHOUSE_USER>,
                password => %*ENV<CLICKHOUSE_PASSWORD>
            });
        RAKU
    my @output;
    react {
        # Relatively long timeout since it might pull the Redis container on first
        # test.
        whenever Promise.in(600) {
            flunk "Timed out";
            done;
        }
        my $proc = Proc::Async.new(@args);
        whenever $proc.stdout.lines {
            @output.push($_);
        }
        whenever $proc.start {
            is .exitcode, 0, 'Successfully ran development script';
            done;
        }
    }
    my @filtered-output = @output.grep(*.starts-with('TEST RESULT:'));
    is @filtered-output[0], 'TEST RESULT: Started', 'Launched process was started';
    is @filtered-output[1], 'TEST RESULT: Has environment CLICKHOUSE_HOST', 'Launched process has expected environment variable (1)';
    is @filtered-output[2], 'TEST RESULT: Has environment CLICKHOUSE_PORT', 'Launched process has expected environment variable (2)';
    is @filtered-output[3], 'TEST RESULT: Has environment CLICKHOUSE_USER', 'Launched process has expected environment variable (3)';
    is @filtered-output[4], 'TEST RESULT: Has environment CLICKHOUSE_PASSWORD', 'Launched process has expected environment variable (4)';
    is @filtered-output[5], 'TEST RESULT: SELECTED 42', 'Can query ClickHouse';
}

done-testing;
