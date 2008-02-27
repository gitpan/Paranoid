# 05_pcleanPath.t

use Paranoid::Filesystem qw(:all);

$|++;
print "1..6\n";

my $test = 1;
my $rv;

# 1 test pcleanPath
$rv = pcleanPath("/usr/sbin/../ccs/share/../../local/bin");
$rv eq '/usr/local/bin' ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 2 test pcleanPath again
$rv = pcleanPath("t/../foo/bar");
$rv eq 'foo/bar' ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 3 test pcleanPath again
$rv = pcleanPath("../t/../foo/bar");
$rv eq '../foo/bar' ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 4 test pcleanPath again
$rv = pcleanPath("../t/../foo/bar/..");
$rv eq '../foo' ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 5 test pcleanPath again
$rv = pcleanPath("../t/../foo/bar/.");
$rv eq '../foo/bar' ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 6 test pcleanPath again
$rv = pcleanPath("/../.././../t/../foo/bar/.");
$rv eq '/foo/bar' ? print "ok $test\n" : print "not ok $test\n";
$test++;

# end 05_pcleanPath.t
