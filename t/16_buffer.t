# 16_buffer.t

use Paranoid::Log;
#use Paranoid::Debug;
#PDEBUG = 20;

$|++;
print "1..5\n";

my $test = 1;

# Load a facility
$rv = enableFacility('foo', 'buffer', 'warn', '=');;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Log something to foo
$rv = plog("warn", "this is a test");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Make sure there's only one entry in the buffer
$rv = scalar Paranoid::Log::Buffer::dump('foo') == 1 ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Log something else to foo
$rv = plog("crit", "this is a test");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Make sure there's only one entry in the buffer
$rv = scalar Paranoid::Log::Buffer::dump('foo') == 1 ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# end 16_buffer.t
