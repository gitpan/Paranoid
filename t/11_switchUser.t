# 11_switchUser.t

use Paranoid::Process qw(:all);
use Paranoid::Input;
FSZLIMIT = 512 * 1024;
#use Paranoid::Debug;
#PDEBUG = 20;

$|++;

my $test = 1;
my ($rv, $id, @tmp, $i);
my (@passwd, $user1, $user2, $uid1, $uid2);
my (@group, $group1, $group2, $gid1, $gid2);

# Prep:  get two valid users & groups to test with
#
# NOTE:  we use user1/group1 to test translation functions (they
#        will probably be root/root|wheel) and user2/group2 to test
#        user switch functions (they will hopefully be unprivileged 
#        users)
if (slurp('/etc/passwd', \@passwd, 1) && @passwd &&
  slurp('/etc/group', \@group, 1) && @group) {
  print "1..7\n";

  # Prune any comment lines (&*^@#4 FreeBSD!?)
  for ($i = 0 ; $i <= $#passwd ; $i++) {
    splice(@passwd, $i, 1) and $i-- if $passwd[$i] =~ /^\s*(?:#.*)?$/;
  }
  for ($i = 0 ; $i <= $#group ; $i++) {
    splice(@group, $i, 1) and $i-- if $group[$i] =~ /^\s*(?:#.*)?$/;
  }

  ($user1, $uid1)  = (split(/:/, $passwd[0]))[0,2];
  ($user2, $uid2)  = (split(/:/, $passwd[$#passwd]))[0,2];
  ($group1, $gid1) = (split(/:/, $group[0]))[0,2];
  ($group2, $gid2) = (split(/:/, $group[$#group]))[0,2];

} else {
  print "1..1\nok 1\n";
  warn "Couldn't find any valid /etc/passwd|group entries to test with -- " .
    "skipping\n";
  exit 0;
}

# 1 - 2 test ptranslateUser
$id = ptranslateUser($user1);
$rv = (defined $id && $id == $uid1) ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;
$id = ptranslateUser('no freaking way:::!');
$rv = ! defined $id ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 3 - 4 test ptranslateGroup
$id = ptranslateGroup($group1);
$rv = (defined $id && $id == $gid1) ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;
$id = ptranslateGroup('no freaking way:::!');
$rv = ! defined $id ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# NOTE:  The following tests will be skipped for non-root users

# 5 test switching just named user
if ($< == 0) {
  if ($pid = fork) {
    waitpid $pid, 0;
    $rv = ! $?;
  } else {
    $rv = switchUser($user2);
    exit ! $rv;
  }
  $rv ? print "ok $test\n" : print "not ok $test\n";
} else {
  print "ok $test\n";
  warn "Skipping remaining tests since test run by non-root user\n";
}
$test++;

# 6 test switching the group
if ($< == 0) {
  if ($pid = fork) {
    waitpid $pid, 0;
    $rv = ! $?;
  } else {
    $rv = switchUser(undef, $group2);
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
    $rv = switchUser($user2, $group2);
    exit ! $rv;
  }
  $rv ? print "ok $test\n" : print "not ok $test\n";
} else {
  print "ok $test\n";
}
$test++;

# end 11_switchUser.t
