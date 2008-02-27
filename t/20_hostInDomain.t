# 06_hostInDomain.t

use Paranoid::Network;

$|++;
print "1..5\n";
$test = 1;

# Test domain match
$rv = hostInDomain('foo.bar.com', 'bar.com');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test hostname match
$rv = hostInDomain('localhost', 'localhost');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test bad hostname
$rv = ! eval "hostInDomain('localh!?`ls`ost', 'localhost')";
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test bad domains
$rv = ! hostInDomain('localhost', 'local?#$host');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test hostname match
$rv = hostInDomain('foo-77.bar99.net', 'dist-22.mgmt.bar-bar.com',
  'bar99.net');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# end 06_hostInDomain.t
