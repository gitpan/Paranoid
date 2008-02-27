# 07_pglob.t

use Paranoid::Filesystem qw(:all);

$|++;
print "1..2\n";

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

# 1 test pglob
$rv = pglob("./t/test_fs/*", \@tmp);
($rv && scalar @tmp == 4 && grep(m#^./t/test_fs/subdir$#, @tmp)) ?
  print "ok $test\n" : print "not ok $test\n";
$test++;

# 2 test pglob
$rv = pglob("./t/test_fs/{o,t}*", \@tmp);
($rv && scalar @tmp == 2 && grep(m#^./t/test_fs/two$#, @tmp)) ?
  print "ok $test\n" : print "not ok $test\n";
$test++;

unlink("t/test_fs/one");
unlink("t/test_fs/two");
unlink("t/test_fs/subdir/three");
rmdir "./t/test_fs/subdir" || warn "subdir: $!\n";
rmdir "./t/test_fs/subdir2" || warn "subdir2: $!\n";
rmdir "./t/test_fs" || warn "test_fs: $!\n";

# end 07_pglob.t
