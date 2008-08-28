# 09_prm.t

use Paranoid::Filesystem qw(:all);
use Paranoid::Debug;
#PDEBUG = 20;

$|++;
print "1..5\n";

my $test = 1;
my %errors;

# Prepare the test directories
mkdir "./t/test_rm";
mkdir "./t/test_rm/foo";
mkdir "./t/test_rm/bar";
mkdir "./t/test_rm/foo/bar";
mkdir "./t/test_rm/foo/bar/roo";
system("touch ./t/test_rm/foo/touched");

# 1 test prm (should fail)
$rv = prm(\%errors, "./t/test_rm");
! $rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 2 test prm (should succeed)
$rv = prm(\%errors, qw(./t/test_rm/bar ./t/test_rm/foo/touched));
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 3 test prmR
system("touch ./t/test_rm/foo/touched");
mkdir "./t/test_rm2/";
mkdir "./t/test_rm2/foo";
symlink "../../test_rm/foo", "./t/test_rm2/foo/bar";
$rv = prmR(\%errors, "./t/test_rm2/foo");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 4 Verify prmR
$rv = (-e "./t/test_rm/foo" && ! -e "./t/test_rm2/foo") ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 5 test prmR w/glob
mkdir "./t/test_rm2/foo";
symlink "../../test_rm/foo", "./t/test_rm2/foo/bar";
$rv = prmR(\%errors, "./t/test_rm*");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# In case the code fails...
system("rm -rf ./t/test_rm* 2>/dev/null");

# end 09_prm.t
