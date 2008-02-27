# 03_detaint.t

use Paranoid::Input qw(:all);

$|++;
print "1..23\n";

my $test = 1;
my @test = (
  [qw(100             number)],
  [qw(-0.5            number)],
  [qw(abc             alphabetic)],
  [qw(abc123          alphanumeric)],
  [qw(THX1138         alphanumeric)],
  [qw(acorliss        login)],
  [qw(foo@bar         email)],
  [qw(foo.foo@bar.com email)],
  [qw(a-.-a";         nometa)],
  [qw(/foo/bar/.foo   filename)],
  [qw(localhost       hostname)],
  [qw(7x.com          hostname)],
  [qw(foo.bar-roo.org hostname)],
  );
my $val;

# 1 - 13 test detainting of valid data
foreach (@test) {
  $rv = detaint($$_[0], $$_[1], \$val);
  $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;
}

# 14 - 22 test detainting of invalid data
@test = (
  [qw(100.00.1        number)],
  [qw(aDb97_          alphabetic)],
  [qw(abc-123         alphanumeric)],
  [qw(1foo            login)],
  [qw(_34@bar.com     email)],
  [qw('`!             nometa)],
  [qw(/^/foo          filename)],
  [qw(-foo.com        hostname)],
  [qw(foo_bar.org     hostname)],
  );
foreach (@test) {
  $rv = detaint($$_[0], $$_[1], \$val);
  ! $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;
}

# 23 test addTaintRegex
addTaintRegex("tel", qr/\d{3}-\d{4}/);
$rv = detaint("345-7211", "tel", \$val);
$rv ? print "ok $test\n" : print "not ok $test\n";
$test++;

# end 03_detaint.t
