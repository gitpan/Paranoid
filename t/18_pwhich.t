# 18_pwhich.t

use Paranoid::Filesystem qw(:all);
#use Paranoid::Debug;
#PDEBUG = 20;

$|++;
print "1..2\n";

my $test = 1;

# 1 test pwhich w/ls
my $match = pwhich('ls');
$rv = defined $match ? 1 : 0;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 2 test for non-existent file
$match = pwhich('lslslslslslsls');
$rv = defined $match ? 0 : 1;
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# end 18_pwhich.t
