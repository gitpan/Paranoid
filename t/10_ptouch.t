# 10_ptouch.t

use Paranoid::Filesystem qw(:all);
#use Paranoid::Debug;
#PDEBUG = 20;

$|++;
print "1..10\n";

my $test = 1;
my @stat;
my %errors;

# 1 test ptouch (should fail)
$rv = ptouch(\%errors, undef, "./t/test_mkdir/foo");
! $rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 2 test ptouch (should succeed)
mkdir "./t/test_touch";
$rv = ptouch(\%errors, undef, "./t/test_touch/foo");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 3 test ptouch with a time in the past
ptouch(\%errors, 1000000, "./t/test_touch/foo", );
@stat = stat("./t/test_touch/foo");
$rv = ($stat[8] == 1000000 && $stat[9] == 1000000) ?
  1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 4 test ptouch w/glob
ptouch(\%errors, undef, "./t/test_touch/bar");
$rv = ptouch(\%errors, 1000000, "./t/test_touch/{foo,bar}");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 5 test ptouchR w/o following links
mkdir "./t/test_touch2";
mkdir "./t/test_touch2/foo";
symlink "../../test_touch", "./t/test_touch2/foo/bar";
$rv = ptouchR(0, \%errors, 10000000, "./t/test_touch2");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 6 Verify touch2 stat
@stat = stat("./t/test_touch2");
$rv = ($stat[8] == 10000000 && $stat[9] == 10000000) ?
  1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 7 Verify touch stat
@stat = stat("./t/test_touch2/foo/bar/foo");
$rv = ($stat[8] == 1000000 && $stat[9] == 1000000) ?
  1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 8 test ptouch w/following links
ptouchR(1, \%errors, 10000000, "./t/test_touch2");
@stat = stat("./t/test_touch2/foo/bar/foo");
$rv = ($stat[8] == 10000000 && $stat[9] == 10000000) ?
  1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 9 test ptouch w/bad path
$rv = ptouchR(0, \%errors, undef, "./t/test_touch2", "./t/test_touch3/foo/bar");
! $rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 10 make sure bad entry is in %errors
$rv = exists $errors{"./t/test_touch3/foo/bar"} ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

system("rm -rf ./t/test_touch* 2>&1");

# end 10_ptouch.t
