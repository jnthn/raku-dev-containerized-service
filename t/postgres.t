use v6.d;
use Test;

# Make sure that we have DB::Pg available for testing.
try require ::('DB::Pg');
my $pg = ::('DB::Pg');
if $pg ~~ Failure {
    skip 'No DB::Pg available for testing';
}
else {
    sub run-and-collect-output-lines(@args) {
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
        return @output;
    }

    subtest 'Basic functionality' => {
        my $test-dev-script = $*PROGRAM.parent.add('test-data/dev-postgres.raku');
        my @args = $*EXECUTABLE, '-I.', $test-dev-script, 'run', $*EXECUTABLE, '-e', q:to/RAKU/;
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
            $db.execute('CREATE TABLE unsaved (a integer)');
            say 'TEST RESULT: Created table';
            say $db.execute('INSERT INTO unsaved (a) VALUES (42)');
            say 'TEST RESULT: Inserted';
            $db.finish;
            RAKU
        my @output = run-and-collect-output-lines(@args);
        my @filtered-output = @output.grep(*.starts-with('TEST RESULT:'));
        is @filtered-output[0], 'TEST RESULT: Started', 'Launched process was started';
        is @filtered-output[1], 'TEST RESULT: Has environment', 'Launched process has expected environment variable';
        is @filtered-output[2], 'TEST RESULT: Connected', 'Launched process could connect';
        is @filtered-output[3], 'TEST RESULT: Queried', 'Launched process could query';
        is @filtered-output[4], 'TEST RESULT: Created table', 'Launched process could create table';
        is @filtered-output[5], 'TEST RESULT: Inserted', 'Launched process could insert';
    }

    subtest 'Without a project/store it is fresh each time' => {
        my $test-dev-script = $*PROGRAM.parent.add('test-data/dev-postgres.raku');
        my @args = $*EXECUTABLE, '-I.', $test-dev-script, 'run', $*EXECUTABLE, '-e', q:to/RAKU/;
            use DB::Pg;
            say 'TEST RESULT: Started';
            my $db = DB::Pg.new(conninfo => %*ENV<DB_CONN_STRING>).db;
            say 'TEST RESULT: Connected';
            try $db.execute('INSERT INTO unsaved (a) VALUES (42)');
            say $! ?? 'TEST RESULT: Insert failed as hoped' !! 'TEST RESULT: Inserted unexpectedly';
            $db.finish;
            RAKU
        my @output = run-and-collect-output-lines(@args);
        my @filtered-output = @output.grep(*.starts-with('TEST RESULT:'));
        is @filtered-output[0], 'TEST RESULT: Started', 'Launched process was started';
        is @filtered-output[1], 'TEST RESULT: Connected', 'Launched process could connect';
        is @filtered-output[2], 'TEST RESULT: Insert failed as hoped',
                'Insert failed as table not persisted from previous run';
    }

    subtest 'Can create with a project/store' => {
        my $test-dev-script = $*PROGRAM.parent.add('test-data/dev-postgres-project.raku');
        try run $*EXECUTABLE, '-I.', $test-dev-script, 'delete'; # Clean up in case of previous failure
        my @args = $*EXECUTABLE, '-I.', $test-dev-script, 'run', $*EXECUTABLE, '-e', q:to/RAKU/;
            use DB::Pg;
            say 'TEST RESULT: Started';
            my $db = DB::Pg.new(conninfo => %*ENV<DB_CONN_STRING>).db;
            say 'TEST RESULT: Connected';
            $db.execute('CREATE TABLE saved (a integer)');
            say 'TEST RESULT: Created table';
            $db.execute('INSERT INTO saved (a) VALUES (42)');
            say 'TEST RESULT: Inserted';
            $db.finish;
            RAKU
        my @output = run-and-collect-output-lines(@args);
        my @filtered-output = @output.grep(*.starts-with('TEST RESULT:'));
        is @filtered-output[0], 'TEST RESULT: Started', 'Launched process was started';
        is @filtered-output[1], 'TEST RESULT: Connected', 'Launched process could connect';
        is @filtered-output[2], 'TEST RESULT: Created table', 'Could create a table';
        is @filtered-output[3], 'TEST RESULT: Inserted', 'Could insert';
    }

    subtest 'With a project/store the data is persisted' => {
        my $test-dev-script = $*PROGRAM.parent.add('test-data/dev-postgres-project.raku');
        my @args = $*EXECUTABLE, '-I.', $test-dev-script, 'run', $*EXECUTABLE, '-e', q:to/RAKU/;
            use DB::Pg;
            say 'TEST RESULT: Started';
            my $db = DB::Pg.new(conninfo => %*ENV<DB_CONN_STRING>).db;
            say 'TEST RESULT: Connected';
            $db.execute('INSERT INTO saved (a) VALUES (99)');
            say 'TEST RESULT: Inserted another value';
            say 'TEST RESULT: Got ' ~ $db.query('SELECT SUM(a) FROM saved').value;
            $db.finish;
            RAKU
        my @output = run-and-collect-output-lines(@args);
        my @filtered-output = @output.grep(*.starts-with('TEST RESULT:'));
        is @filtered-output[0], 'TEST RESULT: Started', 'Launched process was started';
        is @filtered-output[1], 'TEST RESULT: Connected', 'Launched process could connect';
        is @filtered-output[2], 'TEST RESULT: Inserted another value', 'Table was preserved';
        is @filtered-output[3], 'TEST RESULT: Got 141', 'Data was preserved';
    }

    subtest 'Can use a non-default store' => {
        my $test-dev-script = $*PROGRAM.parent.add('test-data/dev-postgres-project.raku');
        try run $*EXECUTABLE, '-I.', $test-dev-script, 'delete', 'other'; # Clean up in case of previous failure
        my @args = $*EXECUTABLE, '-I.', $test-dev-script, '--store=other', 'run', $*EXECUTABLE, '-e', q:to/RAKU/;
            use DB::Pg;
            say 'TEST RESULT: Started';
            my $db = DB::Pg.new(conninfo => %*ENV<DB_CONN_STRING>).db;
            say 'TEST RESULT: Connected';
            $db.execute('CREATE TABLE saved (a integer)');
            say 'TEST RESULT: Created table'; # Wwould fail if not a fresh store
            $db.execute('INSERT INTO saved (a) VALUES (100)');
            say 'TEST RESULT: Inserted';
            say 'TEST RESULT: Got ' ~ $db.query('SELECT SUM(a) FROM saved').value;
            $db.finish;
            RAKU
        my @output = run-and-collect-output-lines(@args);
        my @filtered-output = @output.grep(*.starts-with('TEST RESULT:'));
        is @filtered-output[0], 'TEST RESULT: Started', 'Launched process was started';
        is @filtered-output[1], 'TEST RESULT: Connected', 'Launched process could connect';
        is @filtered-output[2], 'TEST RESULT: Created table', 'Could create a table';
        is @filtered-output[3], 'TEST RESULT: Inserted', 'Could insert';
        is @filtered-output[4], 'TEST RESULT: Got 100', 'Certainly no conflict with store with prior values';
    }

    subtest 'A non-default store is really persisted' => {
        my $test-dev-script = $*PROGRAM.parent.add('test-data/dev-postgres-project.raku');
        my @args = $*EXECUTABLE, '-I.', $test-dev-script, '--store=other', 'run', $*EXECUTABLE, '-e', q:to/RAKU/;
            use DB::Pg;
            say 'TEST RESULT: Started';
            my $db = DB::Pg.new(conninfo => %*ENV<DB_CONN_STRING>).db;
            say 'TEST RESULT: Connected';
            $db.execute('INSERT INTO saved (a) VALUES (200)');
            say 'TEST RESULT: Inserted again';
            say 'TEST RESULT: Got ' ~ $db.query('SELECT SUM(a) FROM saved').value;
            $db.finish;
            RAKU
        my @output = run-and-collect-output-lines(@args);
        my @filtered-output = @output.grep(*.starts-with('TEST RESULT:'));
        is @filtered-output[0], 'TEST RESULT: Started', 'Launched process was started';
        is @filtered-output[1], 'TEST RESULT: Connected', 'Launched process could connect';
        is @filtered-output[2], 'TEST RESULT: Inserted again', 'Could insert another entry';
        is @filtered-output[3], 'TEST RESULT: Got 300', 'Data peristed';
    }

    subtest 'Default store is still fine' => {
        my $test-dev-script = $*PROGRAM.parent.add('test-data/dev-postgres-project.raku');
        my @args = $*EXECUTABLE, '-I.', $test-dev-script, 'run', $*EXECUTABLE, '-e', q:to/RAKU/;
            use DB::Pg;
            say 'TEST RESULT: Started';
            my $db = DB::Pg.new(conninfo => %*ENV<DB_CONN_STRING>).db;
            say 'TEST RESULT: Connected';
            say 'TEST RESULT: Got ' ~ $db.query('SELECT SUM(a) FROM saved').value;
            $db.finish;
            RAKU
        my @output = run-and-collect-output-lines(@args);
        my @filtered-output = @output.grep(*.starts-with('TEST RESULT:'));
        is @filtered-output[0], 'TEST RESULT: Started', 'Launched process was started';
        is @filtered-output[1], 'TEST RESULT: Connected', 'Launched process could connect';
        is @filtered-output[2], 'TEST RESULT: Got 141', 'Data was preserved';
    }

    subtest 'Deleting a store works' => {
        my $test-dev-script = $*PROGRAM.parent.add('test-data/dev-postgres-project.raku');
        lives-ok { run $*EXECUTABLE, '-I.', $test-dev-script, 'delete', 'other' },
            'Can delete a store';
        my @args = $*EXECUTABLE, '-I.', $test-dev-script, '--store=other', 'run', $*EXECUTABLE, '-e', q:to/RAKU/;
            use DB::Pg;
            say 'TEST RESULT: Started';
            my $db = DB::Pg.new(conninfo => %*ENV<DB_CONN_STRING>).db;
            say 'TEST RESULT: Connected';
            try $db.execute('INSERT INTO saved (a) VALUES (200)');
            say $! ?? 'TEST RESULT: Inserted failed' !! 'TEST RESULT: Insert unexpectedly worked';
            $db.finish;
            RAKU
        my @output = run-and-collect-output-lines(@args);
        my @filtered-output = @output.grep(*.starts-with('TEST RESULT:'));
        is @filtered-output[0], 'TEST RESULT: Started', 'Launched process was started';
        is @filtered-output[1], 'TEST RESULT: Connected', 'Launched process could connect';
        is @filtered-output[2], 'TEST RESULT: Inserted failed', 'Insert failed as table is gone';
        lives-ok { run $*EXECUTABLE, '-I.', $test-dev-script, 'delete', 'other' },
                'Can delete a store again';
        lives-ok { run $*EXECUTABLE, '-I.', $test-dev-script, 'delete' },
                'Can delete main store again';
    }
}

done-testing;
