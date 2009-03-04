#!/usr/bin/perl -T
# 05_filesystem.t

use Test::More tests => 97;
use Paranoid;
use Paranoid::Filesystem qw(:all);
use Paranoid::Input qw(addTaintRegex);
use Paranoid::Process qw(ptranslateUser ptranslateGroup);
use Paranoid::Debug;

use strict;
use warnings;

psecureEnv();

my ( $rv, @tmp );

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

# Test preadDir & family
mkdir './t/test_fs',         0777;
mkdir './t/test_fs/subdir',  0777;
mkdir './t/test_fs/subdir2', 0777;
touch('t/test_fs/one');
touch('t/test_fs/two');
touch('t/test_fs/subdir/three');

ok( preadDir( './t/test_fs', \@tmp ), 'preadDir 1' );
is( $#tmp, 3,, 'preadDir 2' );
ok( !preadDir( './t/test_fsss', \@tmp ), 'preadDir 3' );
is( $#tmp, -1,, 'preadDir 4' );
ok( !preadDir( './t/test_fs/one', \@tmp ), 'preadDir 5' );
ok( Paranoid::ERROR =~ /is not a dir/, 'preadDir 6' );
ok( psubdirs( './t/test_fs', \@tmp ), 'psubdirs 1' );
is( $#tmp, 1,, 'psubdirs 2' );
ok( psubdirs( './t/test_fs/subdir', \@tmp ), 'psubdirs 3' );
is( $#tmp, -1,, 'psubdirs 4' );
ok( !psubdirs( './t/test_fs/ssubdir', \@tmp ), 'psubdirs 5' );
is( $#tmp, -1,, 'psubdirs 6' );
ok( pfiles( './t/test_fs', \@tmp ), 'pfiles 1' );
is( $#tmp, 1,, 'pfiles 2' );
ok( !pfiles( './t/test_fss', \@tmp ), 'pfiles 3' );
is( $#tmp, -1,, 'pfiles 4' );
ok( pfiles( './t/test_fs/subdir2', \@tmp ), 'pfiles 5' );
is( $#tmp, -1,, 'pfiles 6' );

# Clean up files
unlink qw(t/test_fs/one t/test_fs/two t/test_fs/subdir/three);
rmdir './t/test_fs/subdir'  || warn "subdir: $!\n";
rmdir './t/test_fs/subdir2' || warn "subdir2: $!\n";
rmdir './t/test_fs'         || warn "test_fs: $!\n";

# Test pcleanPath
$rv = pcleanPath('/usr/sbin/../ccs/share/../../local/bin');
is( $rv, '/usr/local/bin', 'pcleanPath 1' );
$rv = pcleanPath('t/../foo/bar');
is( $rv, 'foo/bar', 'pcleanPath 2' );
$rv = pcleanPath('../t/../foo/bar');
is( $rv, '../foo/bar', 'pcleanPath 3' );
$rv = pcleanPath('../t/../foo/bar/..');
is( $rv, '../foo', 'pcleanPath 4' );
$rv = pcleanPath('../t/../foo/bar/.');
is( $rv, '../foo/bar', 'pcleanPath 5' );
$rv = pcleanPath('/../.././../t/../foo/bar/.');
is( $rv, '/foo/bar', 'pcleanPath 6' );
ok( !eval '$rv = pcleanPath(undef)', 'pcleanPath 7' );

# Test ptranslateLink
mkdir './t/test_fs';
mkdir './t/test_fs/subdir';
symlink '../test_fs/link', './t/test_fs/link';
symlink 'subdir',          './t/test_fs/ldir';

$rv = ptranslateLink('./t/test_fs/ldir');
is( $rv, './t/test_fs/subdir', 'ptranslateLink 1' );
$rv = ptranslateLink('t/test_fs/ldir');
is( $rv, 't/test_fs/subdir', 'ptranslateLink 2' );
$rv = ptranslateLink('t/test_fs/link');
is( $rv, undef, 'ptranslateLink 3' );
ok( Paranoid::ERROR =~ /does not exist/, 'ptranslateLink error message' );
is( Paranoid::Filesystem::MAXLINKS, 20, 'MAXLINKS default value' );
Paranoid::Filesystem::MAXLINKS = 40;
is( Paranoid::Filesystem::MAXLINKS, 40, 'MAXLINKS new value' );

# TODO:  test with optional boolean

# Clean up test files
unlink './t/test_fs/link';
unlink './t/test_fs/ldir';
rmdir './t/test_fs/subdir';
rmdir './t/test_fs';

mkdir './t/test_fs',         0777;
mkdir './t/test_fs/subdir',  0777;
mkdir './t/test_fs/subdir2', 0777;
touch('t/test_fs/one');
touch('t/test_fs/two');
touch('t/test_fs/subdir/three');

ok( pglob( './t/test_fs/*', \@tmp ), 'pglob 1' );
is( $#tmp, 3, 'pglob 2' );
ok( grep( m#^./t/test_fs/subdir$#sm, @tmp ), 'pglob 3' );

ok( pglob( './t/test_fs/{o,t}*', \@tmp ), 'pglob 4' );
is( $#tmp, 1, 'pglob 5' );
ok( grep( m#^./t/test_fs/two$#, @tmp ), 'pglob 6' );

unlink('t/test_fs/one');
unlink('t/test_fs/two');
unlink('t/test_fs/subdir/three');
rmdir './t/test_fs/subdir'  || warn 'subdir: $!\n';
rmdir './t/test_fs/subdir2' || warn 'subdir2: $!\n';
rmdir './t/test_fs'         || warn 'test_fs: $!\n';

my $perms;

# Test pmkdir
ok( pmkdir('./t/test_mkdir/foo/bar/roo'), 'pmkdir 1' );
ok( pmkdir('./t/test_mkdir/foo/bar/roo'), 'pmkdir 2' );
ok( pmkdir( './t/test_mkdir/foo/bar/roo2', 0700 ), 'pmkdir 3' );
is( ( ( stat './t/test_mkdir/foo/bar/roo2' )[2] & 07777 ), 0700, 'pmkdir 4' );

# Cleanup test files
rmdir 't/test_mkdir/foo/bar/roo2';
rmdir 't/test_mkdir/foo/bar/roo';
rmdir 't/test_mkdir/foo/bar';
rmdir 't/test_mkdir/foo';
rmdir 't/test_mkdir';

# Test prm
my %errors;
mkdir './t/test_rm';
mkdir './t/test_rm/foo';
mkdir './t/test_rm/bar';
mkdir './t/test_rm/foo/bar';
mkdir './t/test_rm/foo/bar/roo';
touch('./t/test_rm/foo/touched');

ok( !prm( \%errors, './t/test_rm' ), 'prm 1' );
ok( prm( \%errors, qw(./t/test_rm/bar ./t/test_rm/foo/touched) ), 'prm 2' );
touch('./t/test_rm/foo/touched');
mkdir './t/test_rm2/';
mkdir './t/test_rm2/foo';
symlink '../../test_rm/foo', './t/test_rm2/foo/bar';
ok( prmR( \%errors, './t/test_rm2/foo' ), 'prmR 1' );
mkdir './t/test_rm2/foo';
symlink '../../test_rm/foo', './t/test_rm2/foo/bar';
ok( prmR( \%errors, './t/test_rm*' ), 'prmR 2' );

# Alter built-in regexes to allow for this test
addTaintRegex( 'filename', qr#[[:print:][:space:]]+# );
addTaintRegex( 'fileglob', qr#[[:print:][:space:]]+# );

touch('./t/{foo-to-you and you}');
ok( prmR( \%errors, './t/{foo-to-you and you}' ), 'prmR 3' );

# ptouch
my @stat;

ok( !ptouch( \%errors, undef, './t/test_mkdir/foo' ), 'ptouch 1' );
mkdir './t/test_touch';
ok( ptouch( \%errors, undef,   './t/test_touch/foo' ), 'ptouch 2' );
ok( ptouch( \%errors, 1000000, './t/test_touch/foo' ), 'ptouch 3' );
@stat = stat('./t/test_touch/foo');
is( $stat[8], 1000000, 'checking atime' );
is( $stat[9], 1000000, 'checking mtime' );
ok( ptouch( \%errors, undef, './t/test_touch/bar' ), 'ptouch 4' );
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

# Test pchmod & family
my %data = (
    'ug+rwx'   => 0770,
    'u+rwxs'   => 04700,
    'ugo+rwxt' => 01777,
);
foreach ( keys %data ) {
    $rv = ptranslatePerms($_);
    is( $rv, $data{$_}, 'perms match' );
}
foreach ( '', qw(0990 xr+uG) ) {
    $rv = ptranslatePerms($_);
    is( $rv, undef, 'perms undef' );
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

mkdir './t/test_chmod2',     0777;
mkdir './t/test_chmod2/foo', 0777;
mkdir './t/test_chmod2/roo', 0777;
symlink '../../test_chmod', './t/test_chmod2/foo/bar';

ok( pchmodR( 0, \%errors, 0750, './t/test_chmod2/*' ), 'pchmodR 1' );
@stat = stat('./t/test_chmod/foo');
$rv   = $stat[2] & 07777;
is( $rv, 0700, 'pchmodR 2' );
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

# Test pchown
my ( $user, $group, $uid, $gid, $id );
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

SKIP: {
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

system("rm -rf ./t/test_chown* 2>/dev/null");

# Test pwhich
my $filename = pwhich('ls');
isnt( $filename, undef, 'pwhich 1' );
ok( $filename =~ m#/ls$#sm, 'pwhich 2' );
$filename = pwhich('lslslslslslslslslslsl');
is( $filename, undef, 'pwhich 3' );

# end 05_filesystem.t
