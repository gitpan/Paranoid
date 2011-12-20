#!/usr/bin/perl -T
# 11_module.t

use Test::More tests => 12;
use Paranoid;
use Paranoid::Module;
use Paranoid::Debug;

#PDEBUG = 20;

use strict;
use warnings;

no warnings 'once';

psecureEnv();

ok( loadModule("Paranoid::Input"),          'loadModule 1' );
ok( !loadModule("Paranoid::InputAAAAAAAA"), 'loadModule 2' );
ok( loadModule( "CGI", (qw(start_html)) ), 'loadModule 3' );
ok( eval "start_html('test'); 1", 'loadModule 4' );
ok( !eval "h1('test'); 1",        'loadModule 5' );

ok( loadModule('Socket', 'inet_aton'),      'loadSocket 1' );
ok( ! defined *main::inet_ntoa{CODE},       'loadSocket 2' );
ok( loadModule('Socket', 'inet_ntoa'),      'loadSocket 3' );
ok( defined *main::inet_ntoa{CODE},         'loadSocket 4' );

ok( loadModule('File::Path', '!mkpath'),     'loadFile 1' );
ok( ! defined *main::mkpath{CODE},           'loadFile 2' );
ok( defined *main::rmtree{CODE},             'loadFile 3' );

# end 11_module.t
