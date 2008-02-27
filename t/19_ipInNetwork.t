# 19_ipInNetwork.t

use Paranoid::Network;
use Socket;

$|++;
print "1..6\n";
$test = 1;

# Test CIDR match
$rv = ipInNetwork('127.0.0.1', '127.0.0.0/8');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test alternate CIDR match
$rv = ipInNetwork('127.0.0.1', '127.0.0.0/255.0.0.0');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test IP match
$rv = ipInNetwork('127.0.0.1', '127.0.0.1');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test bad IP match
$rv =  ! eval "ipInNetwork('127.0.s.1', '127.0.0.1')";
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test IP match
$rv =  ipInNetwork('127.0.0.1', '192.168.0.0/24', '127.0.0.0/8');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test bad Networks
$rv =  ! ipInNetwork('127.0.0.1', qw(foo bar roo));
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# end 19_ipInNetwork.t
