# 16_ring.t

use Paranoid::Log;
use Paranoid::Process qw(:pfork);
use Paranoid::Input;
#use Paranoid::Debug;
#PDEBUG = 20;

$SIG{CHLD} = \&sigchld;

$|++;
print "1..4\n";

my $test = 1;
my ($child, $pid, @lines);

# Load a bad facility
enableFacility('foo', 'file', 'warn', '=');
$rv = eval 'plog("warn", "this is a test")';
$rv ? print "not ok $test\n" : print "ok $test\n";
$test++;
disableFacility('foo');

# Load a facility
$rv = enableFacility('foo', 'file', 'warn', '=', './t/foo.log');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Log something to foo
$rv = plog("warn", "this is a test");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Fork some children and have them all log fifty messages each
foreach $child (1 .. 5) {
  unless ($pid = pfork()) {
    sleep 1;
    for (1 .. 50) { plog("warn", "child $child: this is test #$_") };
    exit 0;
  }
}
while (childrenCount()) { sleep 1 };

# Count the number of lines -- should be 251
slurp("./t/foo.log", \@lines, 1);
scalar @lines == 251 ? print "ok $test\n" : print "not ok $test\n";
$test++;

unlink("./t/foo.log");

# end 16_ring.t
