# 23_berkeley.t

use Paranoid::Filesystem qw(prmR);

my (%errors, $db);

$|++;
$test = 1;

if (eval "require Paranoid::BerkeleyDB; 1;") {
  print "1..22\n";

  # Test successful load
  $db = Paranoid::BerkeleyDB->new(DbDir => './t/db', DbName => 'test.db');
  defined $db ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test addDb
  $rv = $db->addDb("test2.db");
  $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test getVal from default database (db should be empty)
  $rv = $db->getVal("foo");
  defined $rv ? print "not ok $test\n" : print "ok $test\n";
  $test++;

  # Test getVal from named database (db should be empty)
  $rv = $db->getVal("foo", "test2.db");
  ! defined $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test getVal from nonexistent named database (db should be empty)
  $rv = $db->getVal("foo", "test9.db");
  ! defined $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test setVal with default database
  $rv = $db->setVal("foo", "bar");
  $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test setVal with named database
  $rv = $db->setVal("foo2", "bar2", "test2.db");
  $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test setVal with named database
  $rv = $db->setVal("roo2", "foo2", "test2.db");
  $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test setVal with nonexistent named database
  $rv = $db->setVal("foo9", "bar9", "test9.db");
  ! $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test getKeys with default database
  $rv = scalar $db->getKeys();
  $rv == 1 ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test getKeys with named database
  $rv = scalar $db->getKeys("test2.db");
  $rv == 2 ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test getKeys with nonexistent named database
  $rv = scalar $db->getKeys("test9.db");
  $rv == 0 ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test getVal from default database
  $rv = $db->getVal("foo");
  (defined $rv && $rv eq 'bar') ? print "ok $test\n" : 
    print "not ok $test\n";
  $test++;

  # Test getVal from named database
  $rv = $db->getVal("foo2", "test2.db");
  (defined $rv && $rv eq 'bar2') ? print "ok $test\n" : 
    print "not ok $test\n";
  $test++;

  # Test setVal deletion with default database
  $rv = $db->setVal("foo");
  $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test setVal deletion with named database
  $rv = $db->setVal("foo2", undef, "test2.db");
  $rv ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test getVal from default database (should be empty)
  $rv = $db->getVal("foo");
  defined $rv ? print "not ok $test\n" : print "ok $test\n";
  $test++;

  # Test getVal from named database (should be empty)
  $rv = $db->getVal("foo2", "test2.db");
  defined $rv ? print "not ok $test\n" : print "ok $test\n";
  $test++;

  # Test purgeDb with default database
  $rv = $db->purgeDb;
  $rv == 0 ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test purgeDb with named database
  $rv = $db->purgeDb("test2.db");
  $rv == 1 ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test purgeDb with nonexistent named database
  $rv = $db->purgeDb("test9.db");
  $rv == -1 ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Test listDbs
  $rv = scalar $db->listDbs;
  $rv == 2 ? print "ok $test\n" : print "not ok $test\n";
  $test++;

  # Cleanup
  prmR(\%errors, "./t/db");

# Fake the tests if BerkeleyDB isn't available
} else {
  warn "BerkeleyDB not available -- skipping all tests...\n";
  print "ok $test\n";
}

# end 23_berkeley.t
