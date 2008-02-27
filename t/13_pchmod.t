# 13_pchmod.t

use Paranoid::Filesystem qw(:all);
#use Paranoid::Debug;
#PDEBUG = 20;

$|++;
print "1..15\n";

my $test = 1;
my (%errors, %data, $rv);

# 1 - 3 Test ptranslatePerms (should all pass)
%data = (
  'ug+rwx'    => 0770,
  'u+rwxs'    => 04700,
  'ugo+rwxt'  => 01777,
  );
foreach (keys %data) {
  $rv = ptranslatePerms($_) == $data{$_} ? 1 : 0;
  $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;
}

# 4 - 6 Test ptranslatePerms (should all fail)
foreach ('', qw(0990 xr+uG)) {
  $rv = defined ptranslatePerms($_) ? 0 : 1;
  $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;
}

# 7 Test pchmod
mkdir "./t/test_chmod";
system("touch ./t/test_chmod/foo ./t/test_chmod/bar");
pchmod(\%errors, "o-rwx", qw(./t/test_chmod/foo ./t/test_chmod/bar));
$rv = pchmod(\%errors, "o+rwx", qw(./t/test_chmod/foo ./t/test_chmod/bar));
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 8 Verify perms
((stat "./t/test_chmod/foo")[2] & 0007) == 0007 ? print "ok $test\n" :
  print "not ok $test\n";
$test++;

# 9 This should fail
$rv = pchmod(\%errors, "o+rwx", qw(./t/test_chmod/foo ./t/test_chmod/bar 
  ./t/test_chmod/roo));
! $rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 10 Test pchmod w/glob
$rv = pchmod(\%errors, 0700, "./t/test_chmod/*");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 11 Test pchmodR w/o following links
mkdir "./t/test_chmod2";
mkdir "./t/test_chmod2/foo";
symlink "../../test_chmod", "./t/test_chmod2/foo/bar";
$rv = pchmodR(0, \%errors, 0750, "./t/test_chmod2/*");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 12 - 13 Verify chmod
((stat "./t/test_chmod/foo")[2] & 07777) == 0700 ? print "ok $test\n" :
  print "not ok $test\n";
$test++;
((stat "./t/test_chmod2/foo")[2] & 07777) == 0750 ? print "ok $test\n" :
  print "not ok $test\n";
$test++;

# 14 Test pchmodR w/following links
$rv = pchmodR(1, \%errors, 0755, "./t/test_chmod2/*");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 15 Verify chmod
((stat "./t/test_chmod/foo")[2] & 07777) == 0755 ? print "ok $test\n" :
  print "not ok $test\n";
$test++;

system("rm -rf ./t/test_chmod* 2>/dev/null");

# end 13_pchmod.t
