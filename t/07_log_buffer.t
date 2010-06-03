#!/usr/bin/perl -T
# 07_log_buffer.t

use Test::More tests => 12;
use Paranoid;
use Paranoid::Log;
use Paranoid::Debug qw(:all);

use strict;
use warnings;

psecureEnv();

ok( enableFacility('foo', 'buffer', 'warn', '='), 'enableFacility 1');
ok( plog("warn", "this is a test"), 'plog 1');
is( scalar(Paranoid::Log::Buffer::dump('foo')), 1, 'dump 1');
ok( plog("crit", "this is a test"), 'plog 2');
is( scalar(Paranoid::Log::Buffer::dump('foo')), 1, 'dump 2');
ok( enableFacility('bar', 'buffer', 'warn', '!'), 'enableFacility 2');
ok( plog("warn", "this is a test"), 'plog 3');
is( scalar(Paranoid::Log::Buffer::dump('bar')), 0, 'dump 3');
ok( plog("crit", "this is a test"), 'plog 4');
is( scalar(Paranoid::Log::Buffer::dump('bar')), 1, 'dump 4');
ok( plog("debug", "this is a test"), 'plog 5');
is( scalar(Paranoid::Log::Buffer::dump('bar')), 2, 'dump 5');


# end 07_log_buffer.t
