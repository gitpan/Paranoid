#!/usr/bin/perl -T
# 11_module.t

use Test::More tests => 5;
use Paranoid;
use Paranoid::Module;

use strict;
use warnings;

psecureEnv();

ok( loadModule("Paranoid::Input"),          'loadModule 1' );
ok( !loadModule("Paranoid::InputAAAAAAAA"), 'loadModule 2' );
ok( loadModule( "CGI", (qw(start_html)) ), 'loadModule 3' );
ok( eval "start_html('test'); 1", 'loadModule 4' );
ok( !eval "h1('test'); 1",        'loadModule 5' );

# end 11_module.t
