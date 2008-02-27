# 06_ptranslateLink.t

use Paranoid::Filesystem qw(:all);

$|++;
print "1..4\n";

my $test = 1;
my $rv;

mkdir "./t/test_fs";
mkdir "./t/test_fs/subdir";
symlink "../test_fs/link", "./t/test_fs/link";
symlink "subdir", "./t/test_fs/ldir";

# 1 test ptranslateLink
$rv = ptranslateLink("./t/test_fs/ldir");
$rv eq './t/test_fs/subdir' ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 2 test ptranslateLink again
$rv = ptranslateLink("t/test_fs/ldir");
$rv eq 't/test_fs/subdir' ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 3 test ptranslateLink with a endlessly recursive link
$rv = ptranslateLink("t/test_fs/link");
(! $rv && Paranoid::ERROR =~ /does not exist/) ? print "ok $test\n" :
  print "not ok $test\n";
$test++;

# 4 Test MAXLINKS
Paranoid::Filesystem::MAXLINKS = 40;
Paranoid::Filesystem::MAXLINKS() == 40 ? print "ok $test\n" : 
  print "not ok $test\n";
$test++;

unlink "./t/test_fs/link";
unlink "./t/test_fs/ldir";
rmdir "./t/test_fs/subdir";
rmdir "./t/test_fs";

# end 06_ptranslateLink.t
