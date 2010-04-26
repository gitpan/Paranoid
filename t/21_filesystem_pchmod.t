#!/usr/bin/perl -T
# 21_filesystem_pchmod.t

use Test::More tests => 21;
use Paranoid;
use Paranoid::Debug;
use Paranoid::Filesystem qw(:all);
use Paranoid::Glob;

#PDEBUG = 20;

psecureEnv();

use strict;
use warnings;

no warnings qw(qw);

my ($rv, @stat, %errors);

# Test pchmod & family
my %data = (
    'ug+rwx'   => 0770,
    'u+rwxs'   => 04700,
    'ugo+rwxt' => 01777,
);
foreach ( keys %data ) {
    $rv = ptranslatePerms($_);
    is( $rv, $data{$_}, "perms match ($_)" );
}
foreach ( '', qw(0990 xr+uG) ) {
    $rv = ptranslatePerms($_);
    is( $rv, undef, "perms undef ($_)" );
}

mkdir './t/test_chmod';
system('touch ./t/test_chmod/foo ./t/test_chmod/bar');
ok( pchmod( \%errors, 'o+rwx', qw(./t/test_chmod/foo ./t/test_chmod/bar) ),
    'pchmod 1' );
@stat = stat('./t/test_chmod/foo');
$rv   = $stat[2] & 0007;
is( $rv, 0007, 'pchmod 2' );
ok( !pchmod(
        \%errors, 'o+rwx', qw(./t/test_chmod/foo ./t/test_chmod/bar
            ./t/test_chmod/roo)
           ),
    'pchmod 3'
  );
ok( pchmod( \%errors, 0700, './t/test_chmod/*' ), 'pchmod 4' );
ok( !pchmod( \%errors, 0755, './t/test_chmod/roooo' ), 'pchmod 5' );

my $glob = Paranoid::Glob->new( globs => [ qw( ./t/test_chmod/* ) ] );
ok( pchmod( \%errors, 0770, $glob ), 'pchmod 6' );
@stat = stat('./t/test_chmod/foo');
$rv   = $stat[2] & 0777;
is( $rv, 0770, 'pchmod 7' );

mkdir './t/test_chmod2',     0777;
mkdir './t/test_chmod2/foo', 0777;
mkdir './t/test_chmod2/roo', 0777;
symlink '../../test_chmod', './t/test_chmod2/foo/bar';

ok( pchmodR( 0, \%errors, 0750, './t/test_chmod2/*' ), 'pchmodR 1' );
@stat = stat('./t/test_chmod/foo');
$rv   = $stat[2] & 07777;
is( $rv, 0770, 'pchmodR 2' );
@stat = stat('./t/test_chmod2/foo');
$rv   = $stat[2] & 07777;
is( $rv, 0750, 'pchmodR 3' );
ok( pchmodR( 0, \%errors, 'o+rx', './t/test_chmod2/*' ), 'pchmodR 4' );
@stat = stat('./t/test_chmod2/foo');
$rv   = $stat[2] & 07777;
is( $rv, 0755, 'pchmodR 5' );
ok( pchmodR( 1, \%errors, 0755, './t/test_chmod2/*' ), 'pchmodR 6' );
@stat = stat('./t/test_chmod/foo');
$rv   = $stat[2] & 07777;
is( $rv, 0755, 'pchmodR 7' );
ok( !pchmodR( 1, \%errors, 0755, './t/test_chmod2/roooo' ), 'pchmodR 7' );

system('rm -rf ./t/test_chmod* 2>/dev/null');

# end 21_filesystem_pchmod.t
