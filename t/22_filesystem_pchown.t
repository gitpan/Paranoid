#!/usr/bin/perl -T
# 22_filesystem_pchown.t

use Test::More tests => 15;
use Paranoid;
use Paranoid::Debug;
use Paranoid::Filesystem qw(:all);
use Paranoid::Glob;
use Paranoid::Process qw(ptranslateUser ptranslateGroup);

#PDEBUG = 20;

psecureEnv();

use strict;
use warnings;

no warnings qw(qw);

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

my ( $user, $group, $uid, $gid, $id, %errors );
mkdir './t/test_chown';
mkdir './t/test_chown2';
mkdir './t/test_chown2/foo';
symlink '../../test_chown', './t/test_chown2/foo/bar';
touch('./t/test_chown/foo');
touch('./t/test_chown/bar');

$user  = 'nobody';
$uid   = ptranslateUser($user);
$group = 'nogroup';
$gid   = ptranslateGroup($group);
unless ( defined $gid ) {
    $group = 'nobody';
    $gid   = ptranslateGroup($group);
}

# NOTE: The following block is skipped due to a bug in all current
# version of Perl involving platforms with unsigned ints for GIDs.  A patch
# has been submitted to bleadperl to fix it.
SKIP: {
    skip( 'Bug in some perls UINT in GIDs', 15);
    skip( 'Non-root user running tests', 15 ) unless $< == 0;
    skip( 'Failed to resolve nobody/nogroup to test with', 15 )
        unless defined $uid and defined $gid;
    ok( pchown( \%errors, $user, undef, "./t/test_chown/*" ), 'pchown 1' );
    $id = ( stat "./t/test_chown/foo" )[4];
    is( $id, $uid, 'pchown 2' );
    ok( pchown( \%errors, undef, $group, "./t/test_chown/*" ), 'pchown 3' );
    $id = ( stat "./t/test_chown/foo" )[5];
    is( $id, $gid, 'pchown 4' );
    ok( pchown( \%errors, 0, 0, "./t/test_chown/*" ), 'pchown 5' );
    ok( pchownR( 0, \%errors, $user, undef, "./t/test_chown2" ),
        'pchownR 1' );
    $id = ( stat "./t/test_chown2/foo" )[4];
    is( $id, $uid, 'pchownR 2' );
    $id = ( stat "./t/test_chown/foo" )[4];
    is( $id, 0, 'pchownR 3' );
    ok( pchown( \%errors, 0, 0, "./t/test_chown/*" ), 'pchown 6' );
    ok( pchownR( 1, \%errors, -1, $group, "./t/test_chown2" ), 'pchownR 4' );
    $id = ( stat "./t/test_chown2/foo" )[5];
    is( $id, $gid, 'pchownR 5' );
    $id = ( stat "./t/test_chown/foo" )[5];
    is( $id, $gid, 'pchownR 6' );
    $id = ( stat "./t/test_chown/foo" )[4];
    is( $id, 0, 'pchownR 7' );
    ok( !pchown( \%errors, -1, $group, "./t/test_chown2/roo" ), 'pchown 7' );
    ok( !pchownR( 1, \%errors, -1, $group, "./t/test_chown2/roo" ),
        'pchownR 8' );
}

system('rm -rf ./t/test_chown* 2>/dev/null');

# end 22_filesystem_pchown.t
