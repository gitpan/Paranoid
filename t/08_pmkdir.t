# 08_pmkdir.t

use Paranoid::Filesystem qw(:all);

$|++;
print "1..3\n";

my $test = 1;
my $perms;

# 1 test pmkdir
$rv = pmkdir("./t/test_mkdir/foo/bar/roo");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 2 test pmkdir
$rv = pmkdir("./t/test_mkdir/foo/bar/roo");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 3 test perms
pmkdir("./t/test_mkdir/foo/bar/roo2", 0700);
$rv = ((stat "./t/test_mkdir/foo/bar/roo2")[2] & 07777) == 0700 ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

rmdir "t/test_mkdir/foo/bar/roo2";
rmdir "t/test_mkdir/foo/bar/roo";
rmdir "t/test_mkdir/foo/bar";
rmdir "t/test_mkdir/foo";
rmdir "t/test_mkdir";

# end 08_pmkdir.t
