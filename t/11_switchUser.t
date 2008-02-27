# 11_switchUser.t

use Paranoid::Process qw(:all);
#use Paranoid::Debug;
#PDEBUG = 20;

$|++;
print "1..7\n";

my $test = 1;
my ($rv, $id);

# 1 - 2 test ptranslateUser
$id = ptranslateUser('root');
$rv = (defined $id && $id == 0) ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;
$id = ptranslateUser('no freaking way:::!');
$rv = ! defined $id ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 3 - 4 test ptranslateGroup
$id = ptranslateGroup('root');
$rv = (defined $id && $id == 0) ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;
$id = ptranslateGroup('no freaking way:::!');
$rv = ! defined $id ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 5 test switching just named user
if ($< == 0) {
  if ($pid = fork) {
    waitpid $pid, 0;
    $rv = ! $?;
  } else {
    $rv = switchUser("nobody");
    exit ! $rv;
  }
  $rv ? print "ok $test\n" : print "not ok $test\n";
} else {
  print "ok $test\n";
}
$test++;

# 6 test switching the group
if ($< == 0) {
  if ($pid = fork) {
    waitpid $pid, 0;
    $rv = ! $?;
  } else {
    $rv = switchUser(undef, "nobody") || switchUser(undef, "nogroup");
    exit ! $rv;
  }
  $rv ? print "ok $test\n" : print "not ok $test\n";
} else {
  print "ok $test\n";
}
$test++;

# 7 test switching both
if ($< == 0) {
  if ($pid = fork) {
    waitpid $pid, 0;
    $rv = ! $?;
  } else {
    $rv = switchUser("nobody", "nobody") || switchUser("nobody", "nogroup");
    exit ! $rv;
  }
  $rv ? print "ok $test\n" : print "not ok $test\n";
} else {
  print "ok $test\n";
}
$test++;

# end 11_switchUser.t
