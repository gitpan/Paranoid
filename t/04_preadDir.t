# 04_preadDir.t

use Paranoid::Filesystem qw(:all);

$|++;
print "1..7\n";

my $test = 1;
my ($rv, @tmp);

sub touch {
  my $filename = shift;
  my $size = shift || 0;

  open(FILE, ">$filename") || die "Couldn't touch file $filename: $!\n";
  while ($size - 80 > 0) {
    print FILE "A" x 79, "\n";
    $size -= 80;
  }
  print FILE "A" x $size;
  close(FILE);
}

mkdir "./t/test_fs", 0777;
mkdir "./t/test_fs/subdir", 0777;
mkdir "./t/test_fs/subdir2", 0777;
touch("t/test_fs/one");
touch("t/test_fs/two");
touch("t/test_fs/subdir/three");

# 1 test preadDir
$rv = preadDir("./t/test_fs", \@tmp);
($rv && scalar @tmp == 4 && grep(m#^./t/test_fs/subdir$#, @tmp)) ?
  print "ok $test\n" : print "not ok $test\n";
$test++;

# 2 test preadDir with a nonexistent directory
$rv = preadDir("./t/test_fsss", \@tmp);
(! $rv && Paranoid::ERROR =~ /does not exist/) ? print "ok $test\n" : 
  print "not ok $test\n";
$test++;

# 3 test preadDir with a file
$rv = preadDir("./t/test_fs/one", \@tmp);
(! $rv && Paranoid::ERROR =~ /is not a directory/) ? print "ok $test\n" : 
  print "not ok $test\n";
$test++;

# 4 test psubdirs
$rv = psubdirs("./t/test_fs", \@tmp);
($rv && scalar @tmp == 2 && grep(m#^./t/test_fs/subdir$#, @tmp)) ?
  print "ok $test\n" : print "not ok $test\n";
$test++;

# 5 test psubdirs again
$rv = psubdirs("./t/test_fs/subdir", \@tmp);
($rv && scalar @tmp == 0) ? print "ok $test\n" : print "not ok $test\n";
$test++;

# 6 test pfiles
$rv = pfiles("./t/test_fs", \@tmp);
($rv && scalar @tmp == 2 && grep(m#^./t/test_fs/one$#, @tmp)) ?
  print "ok $test\n" : print "not ok $test\n";
$test++;

# 7 test pfiles again
$rv = pfiles("./t/test_fs/subdir2", \@tmp);
($rv && scalar @tmp == 0) ? print "ok $test\n" : print "not ok $test\n";
$test++;

unlink("t/test_fs/one");
unlink("t/test_fs/two");
unlink("t/test_fs/subdir/three");
rmdir "./t/test_fs/subdir" || warn "subdir: $!\n";
rmdir "./t/test_fs/subdir2" || warn "subdir2: $!\n";
rmdir "./t/test_fs" || warn "test_fs: $!\n";

# end 04_preadDir.t
