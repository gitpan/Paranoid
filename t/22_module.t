# 22_module.t

use Paranoid::Module;

$|++;
print "1..5\n";
$test = 1;

# Test successful load
$rv = loadModule("Paranoid::Input");
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test unsuccessful load
$rv = loadModule("Paranoid::InputAAAAAAAA");
$rv ? print "not ok $test\n" : print "ok $test\n";
$test++;

# Test successful load w/symbol
$rv = loadModule("CGI", (qw(start_html)));
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test import of symbol
$rv = eval "start_html('test'); 1";
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# Test non-import of symbol
$rv = eval "h1('test'); 1";
$rv ? print "not ok $test\n" : print "ok $test\n";
$test++;

# end 22_module.t
