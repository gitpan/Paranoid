# 24_syslog.t

use Paranoid::Log;
use Paranoid::Module;
#use Paranoid::Debug;
#PDEBUG = 20;

$|++;

my $test = 1;

if (loadModule("Paranoid::Log::Syslog")) {
  print "1..2\n";
} else {
  print "1..1\nok 1\n";
  exit 0;
}

# Load a facility
$rv = enableFacility('local0', 'syslog', 'warn', '=');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Log something to foo
$rv = plog("warn", "this is a test");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# end 24_syslog.t
