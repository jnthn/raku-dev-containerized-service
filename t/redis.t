use v6.d;
use Test;

# Make sure that we have Redis available for testing.
try require ::('Redis');
my $redis = ::('Redis');
if $redis ~~ Failure {
    skip 'No Redis module available for testing';
}
else {
    my $test-dev-script = $*PROGRAM.parent.add('test-data/dev-redis.raku');
    my @args = $*EXECUTABLE, '-I.', $test-dev-script, 'run', $*EXECUTABLE, '-e', q:to/RAKU/;
        use Redis;
        say 'TEST RESULT: Started';
        say %*ENV<REDIS_HOST>:exists
            ?? 'TEST RESULT: Has environment REDIS_HOST'
            !! 'TEST RESULT: Missing environment REDIS_HOST';
        say %*ENV<REDIS_PORT>:exists
            ?? 'TEST RESULT: Has environment REDIS_PORT'
            !! 'TEST RESULT: Missing environment REDIS_PORT';
        my $conn = Redis.new("%*ENV<REDIS_HOST>:%*ENV<REDIS_PORT>", :decode_response);
        say 'TEST RESULT: Connected';
        $conn.set("eggs", "fried");
        say $conn.get("eggs") eq "fried"
            ?? 'TEST RESULT: Queried'
            !! 'TEST RESULT: Unexpected query result';
        $conn.quit;
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
    is @filtered-output[1], 'TEST RESULT: Has environment REDIS_HOST', 'Launched process has expected environment variable (1)';
    is @filtered-output[2], 'TEST RESULT: Has environment REDIS_PORT', 'Launched process has expected environment variable (2)';
    is @filtered-output[3], 'TEST RESULT: Connected', 'Launched process could connect';
    is @filtered-output[4], 'TEST RESULT: Queried', 'Launched process could query';
}

done-testing;
