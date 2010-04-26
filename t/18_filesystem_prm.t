#!/usr/bin/perl -T
# 17_filesystem_prm.t

use Test::More tests => 10;
use Paranoid;
use Paranoid::Debug;
use Paranoid::Filesystem;
use Paranoid::Glob;

#PDEBUG = 20;


psecureEnv();

use strict;
use warnings;

no warnings qw(qw);

my $glob;
my %errors;

sub touch {
    my $filename = shift;
    my $size = shift || 0;
    my $fh;

    open $fh, '>', $filename or die "Couldn't touch file $filename: $!\n";
    while ( $size - 80 > 0 ) {
        print $fh 'A' x 79, "\n";
        $size -= 80;
    }
    print $fh 'A' x $size;
    close $fh;
}

sub prep {
    mkdir './t/test_rm';
    mkdir './t/test_rm/foo';
    mkdir './t/test_rm/bar';
    mkdir './t/test_rm/foo/bar';
    mkdir './t/test_rm/foo/bar/roo';
    touch('./t/test_rm/foo/touched');
    symlink 'foo', './t/test_rm/sym1';
    symlink 'fooo', './t/test_rm/sym2';
}

# start testing
prep();
ok( ! prm( \%errors, './t/test_rm' ), 'prm 1' );
ok( prm( \%errors, qw(./t/test_rm/bar ./t/test_rm/foo/touched) ), 'prm 2' );
touch('./t/test_rm/foo/touched');
ok( prm( \%errors, qw(./t/test_rm/* ./t/test_rm/foo 
    ./t/test_rm/foo/{*/,}*) ) , 'prm 3');

# test w/glob object
prep();
$glob = Paranoid::Glob->new(
    globs   => [ qw(./t/test_rm/* ./t/test_rm/foo 
                ./t/test_rm/foo/{*/,}* ./t/test_rm) ],
    );
ok( prm( \%errors, $glob ), 'prm 4');

# Test recursive function
prep();
ok( prmR( \%errors, './t/test_rm2/foo' ), 'prmR 1' );
mkdir './t/test_rm2/foo';
symlink '../../test_rm/foo', './t/test_rm2/foo/bar';
ok( prmR( \%errors, './t/test_rm*' ), 'prmR 2' );
ok( ! -d './t/test_rm', 'prmR 3' );

ok( prmR( \%errors, './t/test_rm_not_there'), 'prmR 4' );
mkdir './t/test_rm_noperms';
mkdir './t/test_rm_noperms/foo';
chmod 0400, './t/test_rm_noperms';
ok( ! prmR( \%errors, './t/test_rm_noperms/foo'), 'prmR 5' );
chmod 0755, './t/test_rm_noperms';
ok( prmR( \%errors, './t/test_rm_noperms'), 'prmR 6' );

# end 17_filesystem_prm.t
