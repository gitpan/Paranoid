# 14_pchown.t

use Paranoid::Filesystem qw(:all);
use Paranoid::Process qw(ptranslateUser ptranslateGroup);
#use Paranoid::Debug;
#PDEBUG = 20;

$|++;
print "1..13\n";

my $test = 1;
my (%errors, %data, $rv, $name, $id);

mkdir "./t/test_chown";
mkdir "./t/test_chown2";
mkdir "./t/test_chown2/foo";
symlink "../../test_chown", "./t/test_chown2/foo/bar";
system("touch ./t/test_chown/foo ./t/test_chown/bar");

if ($< == 0) {

  # 1 Test pchown w/user
  $rv = pchown(\%errors, 'nobody', undef, "./t/test_chown/*");
  $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # 2 Validate chown
  $id = ptranslateUser('nobody');
  (stat "./t/test_chown/foo")[4] == $id ? print "ok $test\n" :
    print "not ok $test\n";
  $test++;

  # 3 Test pchown w/group
  ($name, $id) = ('nobody', ptranslateGroup('nobody'));
  ($name, $id) = ('nogroup', ptranslateGroup('nogroup')) unless defined $id;
  $rv = pchown(\%errors, undef, $name, "./t/test_chown/*");
  $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # 4 Validate chown
  (stat "./t/test_chown/foo")[5] == $id ? print "ok $test\n" :
    print "not ok $test\n";
  $test++;

  # 5 Test pchownR w/o following links
  pchown(\%errors, 'root', 'root', "./t/test_chown/*");
  $rv = pchownR(0, \%errors, 'nobody', undef, "./t/test_chown2");
  $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # 6 - 7 Validate chown
  $id = ptranslateUser('nobody');
  (stat "./t/test_chown2/foo")[4] == $id ? print "ok $test\n" :
    print "not ok $test\n";
  $test++;
  (stat "./t/test_chown/foo")[4] == 0 ? print "ok $test\n" :
    print "not ok $test\n";
  $test++;

  # 8 Test pchownR w/following links
  ($name, $id) = ('nobody', ptranslateGroup('nobody'));
  ($name, $id) = ('nogroup', ptranslateGroup('nogroup')) unless defined $id;
  pchown(\%errors, 'root', 'root', "./t/test_chown/*");
  $rv = pchownR(1, \%errors, -1, $name, "./t/test_chown2");
  $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # 9 - 10 Validate chown
  (stat "./t/test_chown2/foo")[5] == $id ? print "ok $test\n" :
    print "not ok $test\n";
  $test++;
  (stat "./t/test_chown/foo")[5] == $id ? print "ok $test\n" :
    print "not ok $test\n";
  $test++;

  # 11 Validate -1 arg worked
  (stat "./t/test_chown/foo")[4] == 0 ? print "ok $test\n" :
    print "not ok $test\n";
  $test++;

  # 12 Test bad value pchown
  $rv = pchown(\%errors, -1, $name, "./t/test_chown2/roo");
  ! $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # 13 Test bad value pchownR
  $rv = pchownR(1, \%errors, -1, $name, "./t/test_chown2/roo");
  ! $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

} else {
  for (1 .. 13) { print "ok $test\n" and $test++ };
}

system("rm -rf ./t/test_chown* 2>/dev/null");

# end 14_pchown.t
