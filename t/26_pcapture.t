# 26_pcapture.t

use Paranoid::Process qw(pcapture);
use Paranoid::Debug;
PDEBUG = 0;

$|++;
print "1..5\n";

my $test = 1;
my ($rv, $crv, $out);

# Test pcapture (should succeed)
$rv = pcapture("echo foo", \$crv, \$out);
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test pcapture output
chomp $out;
$out eq 'foo' ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test pcapture (should fail)
$rv = pcapture("echo bar ; exit 3", \$crv, \$out);
warn "RV: $rv\n";
! $rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test pcapture output
chomp $out;
$out eq 'bar' ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test pcapture (should not execute)
$rv = pcapture("HopefullyNoSuchCommand", \$crv, \$out);
$rv == -1 ? print "ok $test\n" : print "not ok $test\n";
$test++;

# end 26_pcapture.t
