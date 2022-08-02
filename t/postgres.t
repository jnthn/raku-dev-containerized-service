use v6.d;
use Test;

# Make sure that we have DB::Pg available for testing.
try require ::('DB::Pg');
my $pg = ::('DB::Pg');
if $pg ~~ Failure {
    skip 'No DB::Pg available for testing';
}
else {
    my $test-dev-script = $*PROGRAM.parent.add('test-data/dev-postgres.raku');
    my @args = $*EXECUTABLE, '-I.', $test-dev-script, $*EXECUTABLE, '-e', q:to/RAKU/;
        use DB::Pg;
        say 'TEST RESULT: Started';
        say %*ENV<DB_CONN_STRING>:exists
            ?? 'TEST RESULT: Has environment'
            !! 'TEST RESULT: Missing environment';
        my $db = DB::Pg.new(conninfo => %*ENV<DB_CONN_STRING>).db;
        say 'TEST RESULT: Connected';
        say $db.query('SELECT (1 + 41) as answer').value == 42
            ?? 'TEST RESULT: Queried'
            !! 'TEST RESULT: Unexpected query result';
        $db.finish;
        RAKU
    my @output;
    react {
        # Relatively long timeout since it might pull the Postgres container on first
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
    is @filtered-output[1], 'TEST RESULT: Has environment', 'Launched process has expected environment variable';
    is @filtered-output[2], 'TEST RESULT: Connected', 'Launched process could connect';
    is @filtered-output[3], 'TEST RESULT: Queried', 'Launched process could query';
}

done-testing;
