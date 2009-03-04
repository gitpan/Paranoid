#!/usr/bin/perl -T
# 07_log_buffer.t

use Test::More tests => 5;
use Paranoid;
use Paranoid::Log;

use strict;
use warnings;

psecureEnv();

ok( enableFacility('foo', 'buffer', 'warn', '='), 'enableFacility 1');
ok( plog("warn", "this is a test"), 'plog 1');
ok( scalar Paranoid::Log::Buffer::dump('foo') == 1, 'dump 1');
ok( plog("crit", "this is a test"), 'plog 2');
ok( scalar Paranoid::Log::Buffer::dump('foo') == 1, 'dump 2');

# end 07_log_buffer.t
