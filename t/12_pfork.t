# 12_pfork.t

use Paranoid::Process qw(:pfork);

$|++;
print "1..3\n";

my $test = 1;
my ($rv, $pid, $c);
my $sigpid = 0;

# Install our signal handler
$SIG{CHLD} = \&sigchld;

# 1 Test pfork child counting
for (1 .. 5) {
  if (pfork() == 0) {
    sleep 3;
    exit 0;
  }
}
$rv = childrenCount() == 5 ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Wait for all children to exit
while (childrenCount()) { sleep 1 };

# 2 Test pfork w/MAXCHILDREN limit
MAXCHILDREN = 3;
for (1 .. 5) {
  if (pfork() == 0) {
    sleep 3;
    exit 0;
  }
}
$c = childrenCount();
$rv = ($c == 2 || $c == 3) ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Wait for all children to exit
while (childrenCount()) { sleep 1 };

# 3 Test installChldHandler
sub testHandler ($$) {
  my $cpid  = shift;
  my $cexit = shift;

  $sigpid = $cpid;
}
installChldHandler(\&testHandler);
MAXCHILDREN = 5;
for (1 .. 5) {
  if (pfork() == 0) {
    sleep 1;
    exit 0;
  }
}
while (childrenCount()) { sleep 1 };
$rv = $sigpid;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# end 12_pfork.t
