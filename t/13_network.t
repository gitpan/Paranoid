#!/usr/bin/perl -T
# 13_network.t

use Test::More tests => 26;
use Paranoid;
use Paranoid::Network;
use Paranoid::Module;
use Paranoid::Debug;
use Socket;

#PDEBUG = 20;

use strict;
use warnings;

psecureEnv();

my $ifconfig = << '__EOF__';
lo        Link encap:Local Loopback  
          inet addr:127.0.0.1  Mask:255.0.0.0
          inet6 addr: ::1/128 Scope:Host
          UP LOOPBACK RUNNING  MTU:16436  Metric:1
          RX packets:199412 errors:0 dropped:0 overruns:0 frame:0
          TX packets:199412 errors:0 dropped:0 overruns:0 carrier:0
          collisions:0 txqueuelen:0 
          RX bytes:90311250 (86.1 MiB)  TX bytes:90311250 (86.1 MiB)

__EOF__

my $iproute = << '__EOF__';
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 16436 qdisc noqueue state UNKNOWN 
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 brd 127.255.255.255 scope host lo
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST> mtu 1500 qdisc pfifo_fast state DOWN qlen 1000
    link/ether 00:d0:f9:6a:cd:d0 brd ff:ff:ff:ff:ff:ff
3: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP qlen 1000
    link/ether 00:12:a8:ff:0e:a1 brd ff:ff:ff:ff:ff:ff
    inet 192.168.2.156/24 brd 192.168.2.255 scope global wlan0
    inet6 fe80::212:a8ff:feff:0ea1/64 scope link 
       valid_lft forever preferred_lft forever
__EOF__

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
ok( scalar( grep !/:/, extractIPs($ifconfig) == 3 ), 'extractIPs 1' );
ok( scalar( grep !/:/, extractIPs($iproute) == 6 ),  'extractIPs 2' );
ok( scalar( grep !/:/, extractIPs( $ifconfig, $iproute ) == 9 ),
    'extractIPs 3' );

SKIP: {
    skip( 'Missing IPv6 support -- skipping IPv6 tests', 12 )
        unless $] >= 5.012 or loadModule('Socket6');

    ok( ipInNetwork( '::1', '::1' ), 'ipInNetwork 7' );
    ok( !ipInNetwork( '::1', '127.0.0.1/8' ), 'ipInNetwork 8' );
    ok( ipInNetwork( '::ffff:192.168.0.5', '192.168.0.0/24' ),
        'ipInNetwork 9' );
    ok( !ipInNetwork( '::ffff:192.168.0.5', '::ffff:192.168.0.0/104' ),
        'ipInNetwork 9' );
    ok( ipInNetwork( 'fe80::212:e9dd:fed9:a1f9', 'fe80::/64' ),
        'ipInNetwork 10' );
    ok( !ipInNetwork( 'fe80::212:e9dd:fed9:a1f9', 'fe81::/64' ),
        'ipInNetwork 11' );
    ok( ipInNetwork( 'fe80::212:e9dd:fed9:a1f9', 'fe80::/60' ),
        'ipInNetwork 12' );
    ok( ipInNetwork( 'fe80::ffff:212:e9dd:fed9:a1f9', 'fe80:0:0:ffff::/60' ),
        'ipInNetwork 13'
        );
    ok( ipInNetwork(
            '::1',                    'fe80:0:0:ffff::/60',
            '::ffff:192.168.0.0/104', '192.168.0.0/24',
            '::1'
            ),
        'ipInNetwork 14'
        );
    ok( scalar extractIPs($ifconfig) == 3, 'extractIPs 4' );
    ok( scalar extractIPs($iproute) == 6,  'extractIPs 5' );
    ok( scalar extractIPs( $ifconfig, $iproute ) == 9, 'extractIPs 6' );
}

# end 13_network.t
