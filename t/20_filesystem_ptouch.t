#!/usr/bin/perl -T
# 20_filesystem_ptouch.t

use Test::More tests => 15;
use Paranoid;
use Paranoid::Debug;
use Paranoid::Filesystem;
use Paranoid::Glob;

#PDEBUG = 20;

psecureEnv();

use strict;
use warnings;

no warnings qw(qw);

my (@stat, %errors, $glob);

ok( !ptouch( \%errors, undef, './t/test_mkdir/foo' ), 'ptouch 1' );
mkdir './t/test_touch';
ok( ptouch( \%errors, undef,   './t/test_touch/foo' ), 'ptouch 2' );
ok( ptouch( \%errors, 1000000, './t/test_touch/foo' ), 'ptouch 3' );
@stat = stat('./t/test_touch/foo');
is( $stat[8], 1000000, 'ptouch 3 checking atime' );
is( $stat[9], 1000000, 'ptouch 3 checking mtime' );
ok( ptouch( \%errors, undef, './t/test_touch/bar' ), 'ptouch 4' );

$glob = Paranoid::Glob->new( globs => [ qw(./t/test_touch/foobar) ] );
ok( ptouch( \%errors, undef, $glob ), 'ptouch 5' );

mkdir './t/test_touch2';
mkdir './t/test_touch2/foo';
symlink '../../test_touch', './t/test_touch2/foo/bar';
ok( ptouchR( 0, \%errors, 10000000, './t/test_touch2' ), 'ptouchR 1' );
@stat = stat('./t/test_touch2');
is( $stat[8], 10000000, 'checking atime' );
@stat = stat('./t/test_touch2/foo/bar/foo');
is( $stat[8], 1000000, 'checking atime' );
ok( ptouchR( 1, \%errors, 10000000, './t/test_touch2' ), 'ptouchR 2' );
@stat = stat('./t/test_touch2/foo/bar/foo');
is( $stat[8], 10000000, 'checking atime' );
is( $stat[9], 10000000, 'checking mtime' );
ok( !ptouchR(
        0, \%errors, undef, './t/test_touch2', './t/test_touch3/foo/bar'
    ),
    'ptouchR 3'
  );
ok( exists $errors{'./t/test_touch3/foo/bar'}, 'error message' );

# Cleanup
system('rm -rf ./t/test_touch* 2>&1');

# end 20_filesystem_ptouch.t
