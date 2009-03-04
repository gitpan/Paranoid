#!/usr/bin/perl -T
# 13_network.t

use Test::More tests => 11;
use Paranoid;
use Paranoid::Network;
use Socket;

psecureEnv();

ok( ipInNetwork( '127.0.0.1', '127.0.0.0/8' ),         'ipInNetwork 1' );
ok( ipInNetwork( '127.0.0.1', '127.0.0.0/255.0.0.0' ), 'ipInNetwork 2' );
ok( ipInNetwork( '127.0.0.1', '127.0.0.1' ),           'ipInNetwork 3' );
ok( !eval "ipInNetwork('127.0.s.1', '127.0.0.1')", 'ipInNetwork 4' );
ok( ipInNetwork( '127.0.0.1', '192.168.0.0/24', '127.0.0.0/8' ),
    'ipInNetwork 5' );
ok( !ipInNetwork( '127.0.0.1', qw(foo bar roo) ), 'ipInNetwork 6' );

ok( hostInDomain( 'foo.bar.com', 'bar.com' ),   'hostInDomain 1' );
ok( hostInDomain( 'localhost',   'localhost' ), 'hostInDomain 2' );
ok( !eval "hostInDomain('localh!?`ls`ost', 'localhost')", 'hostInDomain 3' );
ok( !hostInDomain( 'localhost', 'local?#$host' ), 'hostInDomain 4' );
ok( hostInDomain(
        'foo-77.bar99.net', 'dist-22.mgmt.bar-bar.com', 'bar99.net'
    ),
    'hostInDomain 5'
  );

# end 13_network.t
