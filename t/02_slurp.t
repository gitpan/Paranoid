# 02_slurp.t

use Paranoid::Input;

$|++;
print "1..5\n";

my $test = 1;
my ($val, $f, @lines);

# 1 Test FSZLIMIT;
$val = FSZLIMIT();
$val == 16 * 1024 ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 2 Test setting FSZLIMIT
FSZLIMIT = 64 * 1024;
$val = FSZLIMIT();
$val == 64 * 1024 ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 3 Test reading in 4KB file
FSZLIMIT = 16 * 1024;
$val = int((4 * 1024) / 78);
$f = "./t/test4KB";
open(TEST, "> $f") || die;
for (1 .. $val) { print TEST "1" x 78 . "\n" };
close(TEST);
$val = slurp($f, \@lines);
($val && scalar @lines == int((4 * 1024) / 78)) ? print "ok $test\n" :
  print "not ok $test\n";
unlink $f;
$test++;

# 4 Test reading in 24KB file
$val = int((24 * 1024) / 78);
$f = "./t/test24KB";
open(TEST, "> $f") || die;
for (1 .. $val) { print TEST "1" x 78 . "\n" };
close(TEST);
$val = slurp($f, \@lines);
(! $val && Paranoid::ERROR =~ /is larger than/) ? print "ok $test\n" :
  print "not ok $test\n";
unlink $f;
$test++;

# 5 Test reading in nonexistent file
$f = "./t/foo-test";
$val = slurp($f, \@lines);
(! $val && Paranoid::ERROR =~ /does not exist/) ? print "ok $test\n" :
  print "not ok $test\n";

# end 02_input.t
