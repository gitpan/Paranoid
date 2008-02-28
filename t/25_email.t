# 25_email.t

use Paranoid::Log;
use Paranoid::Module;
#use Paranoid::Debug;
#PDEBUG = 20;

$|++;

my $test = 1;

if (loadModule("Paranoid::Log::Email")) {
  print "1..5\n";
} else {
  print "1..1\nok 1\n";
  warn "Net::SMTP not available -- skipping all tests...\n";
  exit 0;
}

# Load a facility w/invalid host and test
$rv = enableFacility('email', 'email', 'warn', '=', 'localhst0',
  "$ENV{USER}\@localhost", undef, 'Test message -- please ignore');
$rv = plog("warn", "this is a test");
$rv ? print "not ok $test\n" : print "ok $test\n";
$test++;
disableFacility('email');

# Load a facility w/valid host and test
#
# NOTE: It's always possible there is no mail services on the localhost,
#       so we'll always report this to true and just warn on failure
$rv = enableFacility('email', 'email', 'warn', '=', 'localhost',
  "$ENV{USER}\@localhost", undef, 'Test message -- please ignore');
$rv = plog("warn", "this is a test");
print "ok $test\n";
$test++;
disableFacility('email');

# Skip remaining tests if no local mail services are running
unless ($rv) {
  warn "No local mail services found on local host -- skipping " .
    "remaining tests\n";
  for ($test .. 5) { print "ok $_\n" };
  exit 0;
}

# test with multiple recipients
$rv = enableFacility('email', 'email', 'warn', '=', 'localhost',
  ["$ENV{USER}\@localhost", "$ENV{USER}\@localhost"], undef, 
  'Test message -- please ignore');
$rv = plog("warn", "this is a test");
print "ok $test\n";
$test++;
disableFacility('email');

# Load a facility w/invalid sender
#
# NOTE:  we are not going make this an actual test, just warn
#        the user since it's always possible someone has disabled
#        all normal safeguards for local mail services
$rv = enableFacility('email', 'email', 'warn', '=', 'localhost',
  "$ENV{USER}\@localhost", 'user@fooo.coom.neeeet.', 
  'Test message -- please ignore');
$rv = plog("warn", "this is a test");
warn "This test should have failed due to invalid sender domain, but " .
  "could be a local config issue.  Ignoring.\n" if $rv;
print "ok $test\n";
$test++;
disableFacility('email');

# Load a facility w/invalid recipient
#
# NOTE:  we are not going to make this an actual test, just warn
#        the user since it's always possible they are silently 
#        accepting & discarding mail for invalid users.
$rv = enableFacility('email', 'email', 'warn', '=', 'localhost',
  "iHopeTheresNoSuchUserReallyReallyBad\@localhost", undef, 
  'Test message -- please ignore');
$rv = plog("warn", "this is a test");
warn "This test should have failed due to invalid recipient, but " .
  "could be a local config issue.  Ignoring.\n" if $rv;
print "ok $test\n";
$test++;
disableFacility('email');

# end 25_email.t
