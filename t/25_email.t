# 25_email.t

use Paranoid::Log;
use Paranoid::Module;
#use Paranoid::Debug;
#PDEBUG = 20;

$|++;

my $test = 1;

if (loadModule("Paranoid::Log::Email")) {
  print "1..2\n";
} else {
  print "1..1\nok 1\n";
  warn "Net::SMTP not available -- skipping all tests...\n";
  exit 0;
}

# Load a facility
$rv = enableFacility('local0', 'email', 'warn', '=', 'localhost',
  'root@localhost', undef, 'Test message -- please ignore');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Log something to foo
$rv = plog("warn", "this is a test");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# end 25_email.t
