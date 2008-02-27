# 21_stringMatch.t

use Paranoid::Input;

$|++;
print "1..5\n";
$test = 1;

# Test string match
$rv = stringMatch('foo.bar.com', 'bar.com');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test string match
$rv = stringMatch('foo.bar.com', 'combar', qr#\.bar\.#);
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test string match
$rv = stringMatch('foo.bar.com', 'combar', qr#\.baar\.#, '/r\.c/');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test bad input
$rv = ! eval "stringMatch(undef, 'localhost')";
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test bad input
$rv = stringMatch("\n\tFoO\n", 'foo');
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# end 21_stringMatch.t
