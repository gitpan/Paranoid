#!/usr/bin/perl -T
# 02_input.t

use Test::More tests => 58;
use Paranoid;
use Paranoid::Input qw(:all);

use strict;
use warnings;

psecureEnv();

my ( $val, $fh, $f, @lines );

# Test FSZLIMIT
ok( 16 * 1024 == FSZLIMIT, "FSZLIMIT default value" );
FSZLIMIT = 64 * 1024;
ok( 64 * 1024 == FSZLIMIT, "FSZLIMIT assignment" );

# Test slurp
#
# Create a test file
FSZLIMIT = 16 * 1024;
$val = int( ( 4 * 1024 ) / 78 );
$f = "./t/test4KB";
open $fh, '>', $f or die "failed to open file: $!\n";
for ( 1 .. $val ) { print $fh "1" x 78 . "\n" }
close $fh;

ok( slurp( $f, \@lines ), 'slurp\'ing w/4KB file' );
ok( @lines == $val, 'comparing # of lines read' );

# Create a larger test file
$val = int( ( 24 * 1024 ) / 78 );
$f = "./t/test24KB";
open $fh, '>', $f or die "failed to open file: $!\n";
for ( 1 .. $val ) { print $fh "1" x 78 . "\n" }
close $fh;

ok( !slurp( $f, \@lines ), 'slurp\'ing w/24KB file' );
ok( Paranoid::ERROR =~ /is larger than/, 'comparing error message' );

# Test reading non-existant file
$f = "./t/foo-test";

ok( !slurp( $f, \@lines ), 'slurp\'ing non-existent file' );
ok( Paranoid::ERROR =~ /does not exist/, 'comparing error message' );

# Clean up test files
unlink qw(./t/test4KB ./t/test24KB);

# Test detainting of valid data
my @tests = (
    [qw(100             number)],       [qw(-0.5            number)],
    [qw(abc             alphabetic)],   [qw(abc123          alphanumeric)],
    [qw(THX1138         alphanumeric)], [qw(acorliss        login)],
    [qw(foo@bar         email)],        [qw(foo.foo@bar.com email)],
    [qw(a-.-a";         nometa)],       [qw(/foo/bar/.foo   filename)],
    [qw(localhost       hostname)],     [qw(7x.com          hostname)],
    [qw(foo.bar-roo.org hostname)],
);
foreach (@tests) {
    ok( detaint( $$_[0], $$_[1], \$val ), "detaint $$_[0] ($$_[1])" );
    is( $val, $$_[0], 'strings match' );
}

# Test detainting of invalid data
@tests = (
    [qw(100.00.1        number)],       [qw(aDb97_          alphabetic)],
    [qw(abc-123         alphanumeric)], [qw(1foo            login)],
    [qw(_34@bar.com     email)],        [qw('`!             nometa)],
    [qw(/^/foo          filename)],     [qw(-foo.com        hostname)],
    [qw(foo_bar.org     hostname)],
);
foreach (@tests) {
    ok( !detaint( $$_[0], $$_[1], \$val ), "detaint $$_[0] ($$_[1])" );
    is( $val, undef, 'value is undef' );
}

# Test non-existent regex
ok( !detaint( 'foo', 'arg', \$val ), 'detaint w/unknown regex' );

# Test addTaintRegex
ok( addTaintRegex( 'tel', qr/\d{3}-\d{4}/ ), 'addTaintRegex' );
ok( detaint( '345-7211', 'tel', \$val ), 'detaint 345-7211 tel' );
is( $val, '345-7211',, 'strings match' );

# Test stringMatch
my $long = << '__EOF__';
This is a semi-random string of gibberish that merely pretends 
to be a paragraph in search of a meaning.  I only want to 
through enough content at my poor, pitiful subroutine to verify 
that it actually works.

It probably won't, though.  And that's a damned shame.
__EOF__
my @words1 = qw( /semi/ gibberish pitiful /ara/ );
my @words2 = qw( /exa/ /on.f/ );
ok( stringMatch( $long, @words1 ), 'stringMatch (good test)' );
ok( !stringMatch( $long, @words2 ), 'stringMatch (bad test)' );

# end 02_input.t
