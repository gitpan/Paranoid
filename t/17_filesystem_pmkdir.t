#!/usr/bin/perl -T
# 16_filesystem_pmkdir.t

use Test::More tests => 8;
use Paranoid;
use Paranoid::Debug;
use Paranoid::Filesystem;
use Paranoid::Glob;

#PDEBUG = 20;

psecureEnv();

use strict;
use warnings;

my $cmask = umask;
my $glob;

ok( pmkdir( 't/test/{ab,cd,ef{1,2}}' ), 'pmkdir 1' );
foreach (qw(t/test/ab t/test/cd t/test/ef1 t/test/ef2 t/test)) {
  rmdir $_ };

ok( ! pmkdir( 't/test/{ab,cd,ef{1,2}}', 0555 ), 'pmkdir 2' );
rmdir 't/test';

$glob = Paranoid::Glob->new(
    globs   => ['t/test/{ab,cd,ef{1,2}}'], 
    );
ok( pmkdir( $glob ), 'pmkdir 3' );
foreach (qw(t/test/ab t/test/cd t/test/ef1 t/test/ef2 t/test)) {
  rmdir $_ };

$glob = Paranoid::Glob->new(
    literals   => ['t/test/{ab,cd,ef{1,2}}'], 
    );
ok( pmkdir( $glob ), 'pmkdir 4' );
{ 
    no warnings 'qw';
    foreach (qw(t/test/{ab,cd,ef{1,2}} t/test)) { rmdir $_ };
}

ok( ! pmkdir(undef), 'pmkdir 5');
ok( ! pmkdir('t/test', 'mymode'), 'pmkdir 6');

ok( pmkdir('t/test_pmkdir/with/many/subdirs'), 'pmkdir 7');
ok( pmkdir('t/test_pmkdir/with/many/subdirs/again'), 'pmkdir 8');

system 'rm -rf t/test_pmkdir';

# end 16_filesystem_pmkdir.t
