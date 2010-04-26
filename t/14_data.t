#!/usr/bin/perl -T
# 14_data.t

use Test::More tests => 17;
use Paranoid;
use Paranoid::Data;
use Socket;

use strict;
use warnings;

psecureEnv();

my $sScalar = 'foo';
my @sArray  = qw( one two three four);
my %sHash   = (
    a     => 'A Value',
    b     => 'B Value',
    c     => 'C Value',
    );
my ($tScalar, @tArray, %tHash, $rv);

# Simple one-level copies
$rv = deepCopy(\$sScalar, \$tScalar);
is( $rv, 1, 'deepCopy scalar ref 1');
is( $tScalar, 'foo',    'deepCopy scalar ref 2');
$rv = deepCopy(\@sArray, \@tArray);
is( $rv, 4, 'deepCopy array ref 1');
is( $tArray[2], 'three', 'deepCopy array ref 2');
$rv = deepCopy(\%sHash, \%tHash);
is( $rv, 3, 'deepCopy hash ref 1');
is( $tHash{c}, 'C Value', 'deepCopy hash ref 2');

# Simple two-level copies
@sArray = (
    qw( one two ), 
    [ qw( subone subtwo subtree ) ],
    qw( three four ),
    );
%sHash = (
    a       => 'A Value',
    b       => {
        Key     => 'b',
        Value   => 'Hash Ref',
        },
    c       => 'C Value',
    );
$rv = deepCopy(\@sArray, \@tArray);
is( $rv, 8, 'deepCopy array ref 3');
is( $tArray[2][1], 'subtwo', 'deepCopy array ref 4');
$rv = deepCopy(\%sHash, \%tHash);
is( $rv, 5, 'deepCopy hash ref 3');
is( $tHash{b}{Value}, 'Hash Ref', 'deepCopy hash ref 4');

# More complex structures
$sHash{d}   = {
    Key         => 'd',
    Value       => [ @sArray ],
    };
$sArray[3] = $sHash{b};
$rv = deepCopy(\@sArray, \@tArray);
is( $rv, 10, 'deepCopy array ref 5');
is( $tArray[3]{Key}, 'b', 'deepCopy array ref 6');
$rv = deepCopy(\%sHash, \%tHash);
is( $rv, 16, 'deepCopy hash ref 5');
is( $tHash{d}{Value}[2][1], 'subtwo', 'deepCopy hash ref 6');

# Expected failures
ok( !eval 'deepCopy(\%sHash, \@tArray)', 'deepCopy fail 1');
ok( !eval 'deepCopy($sScalar, $tScalar)', 'deepCopy fail 2');
$sArray[2][3] = $sHash{d};
$rv = deepCopy(\@sArray, \@tArray);
is( $rv, 0, 'deepCopy fail 3');

# end 14_data.t
