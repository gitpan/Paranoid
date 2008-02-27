# 15_log.t

use Paranoid::Log qw(:all);

$|++;
print "1..9\n";

my $test = 1;

# Load a non-existent facility
$rv = enableFacility('foo', 'stderrrrrrrrrrrrr', 'warn', '+');;
$rv ? print "not ok $test\n" : print "ok $test\n";
$test++;

# Load a facility
$rv = enableFacility('foo', 'stderr', 'warn', '+');;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Log something to stderr
$rv = plog("crit", "this is a test");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Log something to stderr
$rv = psyslog("crit", "this is a test");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Remove the facility
$rv = disableFacility('foo');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Log something to stderr
$rv = psyslog("crit", "this is a test");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test synoynms
$rv = psyslog("panic", "this is a test");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;
$rv = psyslog("error", "this is a test");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;
$rv = psyslog("warning", "this is a test");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# end 15_log.t
