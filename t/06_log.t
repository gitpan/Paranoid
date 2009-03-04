#!/usr/bin/perl -T
# 06_log.t

use Test::More tests => 9;
use Paranoid;
use Paranoid::Log qw(:all);

psecureEnv();

# Redirect STDERR to /dev/null
close STDERR;
open STDERR, '>', '/dev/null';

# Load a non-existent facility
ok( !enableFacility( 'foo', 'stderrrrrrrrrrrrr', 'warn', '+' ),
    'enableFacility 1' );
ok( enableFacility( 'foo', 'stderr', 'warn', '+' ), 'enableFacility 2' );
ok( plog( "crit", "this is a test" ), 'plog 1' );
ok( psyslog( "crit", "this is a test" ), 'psyslog 1' );
ok( disableFacility('foo'), 'disableFacility 1' );
ok( psyslog( "crit",    "this is a test" ), 'psyslog 2' );
ok( psyslog( "panic",   "this is a test" ), 'psyslog 3' );
ok( psyslog( "error",   "this is a test" ), 'psyslog 4' );
ok( psyslog( "warning", "this is a test" ), 'psyslog 5' );

# end 06_log.t
