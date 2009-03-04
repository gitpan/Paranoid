#!/usr/bin/perl -T
# 08_log_file.t

use Test::More tests => 6;
use Paranoid;
use Paranoid::Log;
use Paranoid::Process qw(:pfork);
use Paranoid::Input;

psecureEnv();

$SIG{CHLD} = \&sigchld;

my ($child, $pid, @lines);

# Load a bad facility
ok( enableFacility('foo', 'file', 'warn', '='), 'enableFacility 1');
ok( !eval "plog('warn', 'this is a test')", 'plog 1');
ok( disableFacility('foo'), 'disableFacility');
ok( enableFacility('foo', 'file', 'warn', '=', './t/foo.log'), 
    'enableFacility 2');
ok( plog("warn", "this is a test"), 'plog 2');

# Fork some children and have them all log fifty messages each
foreach $child (1 .. 5) {
  unless ($pid = pfork()) {
    sleep 1;
    for (1 .. 50) { plog('warn', "child $child: this is test #$_") };
    exit 0;
  }
}
while (childrenCount()) { sleep 1 };

# Count the number of lines -- should be 251
slurp("./t/foo.log", \@lines, 1);
ok( scalar @lines == 251, 'line count');

unlink("./t/foo.log");

# end 08_log_file.t
