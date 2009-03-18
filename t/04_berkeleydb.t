#!/usr/bin/perl -T
# 04_berkeleydb.t

use Test::More tests => 34;
use Paranoid;
use Paranoid::Filesystem qw(prmR);
use Paranoid::Module;

use strict;
use warnings;

psecureEnv();

my ( $rv, %errors, $db );

$rv = loadModule("Paranoid::BerkeleyDB");

SKIP: {
    skip( 'BerkeleyDB module not found', 34 ) unless $rv;

    $db = Paranoid::BerkeleyDB->new( DbDir => './t/db', DbName => 'test.db' );
    isnt( $db, undef, 'got db handle' );
    isa_ok( $db, 'Paranoid::BerkeleyDB' );
    ok( $db->addDb("test2.db"), 'added test2.db' );
    $rv = $db->getVal('foo');
    is( $rv, undef, 'no such record' );
    $rv = $db->getVal( 'foo', 'test2.db' );
    is( $rv, undef, 'no such record 2' );
    $rv = $db->getVal( 'foo', 'test9.db' );
    is( $rv, undef, 'no such record 3' );
    like( Paranoid::ERROR, qr/nonexistent/, 'no such database' );
    ok( $db->setVal( 'foo', 'bar' ), 'add record' );
    ok( $db->setVal( 'foo', 'bar2', 'test2.db' ), 'add record 2' );
    ok( $db->setVal( 'roo', 'foo2', 'test2.db' ), 'add record 3' );
    Paranoid::ERROR = '';
    ok( !$db->setVal( 'foo9', 'bar9', 'test9.db' ), 'no such database' );
    like( Paranoid::ERROR, qr/nonexistent/, 'error message' );
    $rv = scalar $db->getKeys();
    is( $rv, 1, 'get keys 1' );
    $rv = scalar $db->getKeys('test2.db');
    is( $rv, 2, 'get keys 2' );
    Paranoid::ERROR = '';
    $rv = scalar $db->getKeys('test9.db');
    is( $rv, 0, 'no such database' );
    like( Paranoid::ERROR, qr/nonexistent/, 'error message' );
    $rv = $db->getVal('foo');
    is( $rv, 'bar', 'get record 1' );
    $rv = $db->getVal( 'foo', 'test2.db' );
    is( $rv, 'bar2', 'get record 2' );
    ok( $db->setVal('foo'), 'delete record 1' );
    $rv = scalar $db->getKeys();
    is( $rv, 0, 'get keys 3' );
    ok( $db->setVal( 'foo', undef, 'test2.db' ), 'delete record 2' );
    $rv = scalar $db->getKeys('test2.db');
    is( $rv, 1, 'get keys 4' );
    Paranoid::ERROR = '';
    ok( !$db->setVal( 'foo', undef, 'test9.db' ), 'no such database' );
    like( Paranoid::ERROR, qr/nonexistent/, 'error message' );
    $rv = $db->getVal('foo');
    is( $rv, undef, 'no such record' );
    $rv = $db->getVal( 'foo', 'test2.db' );
    is( $rv, undef, 'no such record 2' );
    $rv = $db->purgeDb;
    is( $rv, 0, 'purge db 1' );
    $rv = $db->purgeDb('test2.db');
    is( $rv, 1, 'purge db 2' );
    Paranoid::ERROR = '';
    $rv = $db->purgeDb('test9.db');
    is( $rv, -1, 'no such database' );
    like( Paranoid::ERROR, qr/nonexistent/, 'error message' );
    $rv = scalar $db->getKeys('test2.db');
    is( $rv, 0, 'get keys 5' );
    $rv = scalar $db->listDbs;
    is( $rv, 2, 'listDbs' );

    foreach ( 1 .. 20 ) {
        $db->setVal( $_ => $_ ** 2 );
    }

    sub testIterator {
       my $db  = shift;
       my $key = shift;
       my $val = shift;

       #warn "Power of $key is $val\n";
       $db->setVal( $key, undef );
    }

    $rv = $db->getKeys(undef, \&testIterator);
    is( $rv, 20, 'iterator 1');
    $rv = $db->getKeys;
    is( $rv, 0, 'iterator 2');

    # Cleanup
    prmR( \%errors, "./t/db" );
}


# end 04_berkeleydb.t
