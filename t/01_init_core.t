#!/usr/bin/perl -T
# 01_init_core.t

use Test::More tests => 14;

use strict;
use warnings;

ok( eval 'require Paranoid;',             'Loaded Paranoid' );
ok( eval 'require Paranoid::Args;',       'Loaded Paranoid::Args' );
ok( eval 'require Paranoid::Debug;',      'Loaded Paranoid::Debug' );
ok( eval 'require Paranoid::Filesystem;', 'Loaded Paranoid::Filesystem' );
ok( eval 'require Paranoid::Input;',      'Loaded Paranoid::Input' );
ok( eval 'require Paranoid::Lockfile;',   'Loaded Paranoid::Lockfile' );
ok( eval 'require Paranoid::Log;',        'Loaded Paranoid::Lockfile' );
ok( eval 'require Paranoid::Module;',     'Loaded Paranoid::Module' );
ok( eval 'require Paranoid::Network;',    'Loaded Paranoid::Network' );
ok( eval 'require Paranoid::Process;',    'Loaded Paranoid::Process' );

eval 'Paranoid->import;';

ok( psecureEnv('/bin:/sbin'), 'psecureEnv 1' );
is( $ENV{PATH}, '/bin:/sbin', 'Validated PATH' );
ok( psecureEnv(), 'psecureEnv 2' );
is( $ENV{PATH}, '/bin:/usr/bin', 'Validated PATH' );

# end 01_init_core.t
