#!/usr/bin/perl -T
# 09_log_syslog.t

use Test::More tests => 2;
use Paranoid;
use Paranoid::Log;
use Paranoid::Module;

psecureEnv();

SKIP: {
    skip( "Unix::Syslog module not found", 2 )
        unless loadModule('Paranoid::Log::Syslog');

    ok( enableFacility( 'local0', 'syslog', 'warn', '=' ),
        'enableFacility 1' );
    ok( plog( "warn", "this is a test" ), 'plog 1' );
}

# end 09_log_syslog.t
