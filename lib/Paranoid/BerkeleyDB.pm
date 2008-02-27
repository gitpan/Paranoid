# Paranoid::BerkeleyDB -- Paranoid BerkeleyDB Usage
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: BerkeleyDB.pm,v 0.2 2008/02/27 06:46:39 acorliss Exp $
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#
#####################################################################

=head1 NAME

Paranoid::BerkeleyDB -- Paranoid BerkeleyDB Usage Routines

=head1 MODULE VERSION

$Id: BerkeleyDB.pm,v 0.2 2008/02/27 06:46:39 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::BerkeleyDB;

  $db = Paranoid::BerkeleyDB->new(DbDir => '/tmp', DbName => 'foo.db');
  $rv = $db->addDb($dbname);

  $val = $db->getVal($key);
  $val = $db->getVal($key, $dbname);

  $rv = $db->setVal($key, $val);
  $rv = $db->setVal($key, $val, $dbname);

  @keys = $db->getKeys();
  @keys = $db->getKeys($dbname);

  $db->purgeDb();
  $db->purgeDb($dbname);

  @dbs = $db->listDbs();

=head1 REQUIREMENTS

Paranoid

Paranoid::Debug

Paranoid::Filesystem

Paranoid::Lockfile

BerkeleyDB;

=head1 DESCRIPTION

This provides a OO-based wrapper for BerkeleyDB that creates concurrent-access
BerkeleyDB databases.  Each object can have multiple databases, but all
databases within an object will use a single shared environment.  To make this
multiprocess safe an external lock file is used with only one process at a
time allowed to hold an exclusive write lock, even if the write is intended
for a different database.

Databases and environments are created using the defaults for both the
environment and the databases.  This won't be the highest performance
implementation for BerkeleyDB, but it should be the safest and most robust.
This is part of the Paranoid Suite, after all.

Limitations:  all keys and all values must be valid strings.  That means that
attempting to set a valid key's associated value to B<undef> will fail to add
that key to the database.

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::BerkeleyDB;

use strict;
use warnings;
use vars qw($VERSION);
use Paranoid;
use Paranoid::Debug;
use Paranoid::Lockfile;
use Paranoid::Filesystem qw(pmkdir);
use BerkeleyDB;
use Carp;

($VERSION)    = (q$Revision: 0.2 $ =~ /(\d+(?:\.(\d+))+)/);

#####################################################################
#
# BerkeleyDB code follows
#
#####################################################################

=head1 METHODS

=head2 new

  $db = Paranoid::BerkeleyDB->new(DbDir => '/tmp', DbName => 'foo.db');

Creating an object will fail if the BerkeleyDB module is not present and
return undef.  Two arguments are required:  B<DbDir> which is the path to the
directory where the database files will be stored, and B<DbName> which is the
filename of the database itself.  If B<DbDir> doesn't exist it will be created
for you automatically.

This method will create a BerkeleyDB Environment and to support multiprocess 
transactions.

Any errors in the operation will be stored in B<Paranoid::ERROR>.

=cut

sub new (@) {
  my $class = shift;
  my %init  = (
    DbDir   => undef,
    DbName  => undef,
    Dbs     => {},
    DbEnv   => undef,
    );
  my %args  = @_;
  my $dbdir = defined $args{DbDir}  ? $args{DbDir}  : 'undef';
  my $dbnm  = defined $args{DbName} ? $args{DbName} : 'undef';
  my ($self, $tmp);

  pdebug("entering w/DbDir => \"$dbdir\", DbName => \"$dbnm\"",
    9);
  pIn();

  # Make sure $dbdir & $dbnm are defined and BerkeleyDB is available
  if (defined $dbdir and defined $dbnm) {

    # Create the directory
    if (pmkdir($dbdir, 0750)) {

      # Create lock file and lock it while doing initialization.  I know, this
      # isn't ideal when creating temporary objects that need only read
      # access, but it's the only way to avoid race conditions if this is the
      # process that creates the database.
      plock("$dbdir/db.lock");

      # Create and bless the object reference
      @init{qw(DbDir DbName)} = ($dbdir, $dbnm);
      $self = \%init;
      bless $self, $class;

      # Initialize the environment
      no strict 'subs';
      if (defined($tmp = BerkeleyDB::Env->new(
        '-Home'     => $dbdir,
        '-ErrFile'  => \*STDERR,
        '-Flags'    => DB_CREATE | DB_INIT_CDB | DB_INIT_MPOOL,
        ))) {

        # Create the database
        $self->{DbEnv} = $tmp;
        $tmp = BerkeleyDB::Hash->new(
          '-Filename'   => $dbnm,
          '-Env'        => $self->{DbEnv},
          '-Flags'      => DB_CREATE,
          );

        # Save the default db info
        if (defined $tmp) {
          $self->{Dbs}->{$dbnm} = $tmp;

        # Report any errors
        } else {
          $self = undef;
          Paranoid::ERROR = pdebug("failed to create BerkeleyDB $dbnm: $!", 
            9);
        }

      # Report any errors
      } else {
        $self = undef;
        Paranoid::ERROR = pdebug("failed to initialize BerkeleyDB Env: $!", 
          9);
      }

      # Unlock the database
      punlock("$dbdir/db.lock");

    # Report the error
    } else {
      Paranoid::ERROR = 
        pdebug("failed to create directory $dbdir: @{[ Paranoid::ERROR ]}", 
        9);
    }
  }

  pOut();
  pdebug("leaving w/rv: " . (defined $self ? $self : 'undef'),
    9);

  return $self;
}

=head2 addDb

  $rv = $db->addDb($dbname);

The adds another database to the current object and environment.  Calling this
method does require an exclusive write to the database to prevent race
conditions.

Any errors in the operation will be stored in B<Paranoid::ERROR>.

=cut

sub addDb ($$) {
  my $self  = shift;
  my $dbnm  = shift;
  my $dbdir = $self->{DbDir};
  my $n     = defined $dbnm ? $dbnm : 'undef';
  my $rv    = 0;
  my $db;

  pdebug("entering w/($n)", 9);
  pIn();

  # Make sure a valid name was passed and it hasn't already been created
  if (defined $dbnm and ! exists ${ $self->{Dbs} }{$dbnm}) {

    # Get exclusive lock
    plock("$dbdir/db.lock");
  
    $db = BerkeleyDB::Hash->new(
      '-Filename'   => $dbnm,
      '-Env'        => $self->{DbEnv},
      '-Flags'      => DB_CREATE,
      );

    # Store & report the result
    $rv = defined $db ? 1 : 0;
    if ($rv) {
      $self->{Dbs}->{$dbnm} = $db;
      pdebug("added new database: $dbnm", 10);
    } else {
      Paranoid::ERROR = 
        pdebug("failed to add new database: $dbnm", 10);
    }

    # Release lock
    punlock("$dbdir/db.lock");
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 getVal

  $val = $db->getVal($key);
  $val = $db->getVal($key, $dbname);

The B<getVal> method retrieves the associated string to the passed key.
Called with one argument the method uses the default database.  Otherwise, a
second argument specifying the specific database is required.

Requesting a non-existent key or from a nonexistent database will result in 
an undef being returned.  In the case of the latter an error message will also
be set in B<Paranoid::ERROR>.

=cut

sub getVal ($$;$) {
  my $self    = shift;
  my $key     = shift;
  my $db      = shift;
  my $k       = defined $key ? $key : 'undef';
  my $d       = defined $db  ? $db  : 'undef';
  my $dref    = $self->{Dbs};
  my $dbdir   = $self->{DbDir};
  my ($val, $v);

  pdebug("entering w/($k)($d)", 9);
  pIn();

  # Set the default database name if it wasn't passed
  unless (defined $db) {
    $db = $self->{DbName};
    pdebug("setting db to default ($db)", 10);
  }

  # Make sure database exists
  if (exists $$dref{$db}) {

    # Lock database for read mode
    plock("$dbdir/db.lock", 'shared');

    unless ($$dref{$db}->db_get($key, $val) == 0) {
      pdebug("no such key exists ($key)", 10);
    }

    # Unlock database
    punlock("$dbdir/db.lock");

  # Report invalid database
  } else {
    Paranoid::ERROR = pdebug("attempted to access a " .
      "nonexistent database ($db)", 9);
  }

  $v = defined $val ? $val : 'undef';
  pOut();
  pdebug("leaving w/rv: $v", 9);

  return $val;
}

=head2 setVal

  $rv = $db->setVal($key, $val);
  $rv = $db->setVal($key, $val, $dbname);

This method adds or updates an associative pair.  If the passed value is
B<undef> the key is deleted from the database.  If no database is explicitly
named it is assumed that the default database is the one to work on.

Requesting a non-existent key or from a nonexistent database will result in 
an undef being returned.  In the case of the latter an error message will also
be set in B<Paranoid::ERROR>.

=cut

sub setVal ($$;$$) {
  my $self    = shift;
  my $key     = shift;
  my $val     = shift;
  my $db      = shift;
  my $k       = defined $key ? $key : 'undef';
  my $v       = defined $val ? $val : 'undef';
  my $d       = defined $db  ? $db  : 'undef';
  my $dref    = $self->{Dbs};
  my $dbdir   = $self->{DbDir};
  my $rv      = 0;
  my $lock;

  pdebug("entering w/($k)($v)($d)", 9);
  pIn();

  # Set the default database name if it wasn't passed
  unless (defined $db) {
    $db = $self->{DbName};
    pdebug("setting db to default ($db)", 10);
  }

  # Make sure database exists
  if (exists $$dref{$db}) {

    # Make sure key is defined
    if (defined $key) {

      # Lock database for write mode
      plock("$dbdir/db.lock");
      $lock = $$dref{$db}->cds_lock;

      # Set the new value
      if (defined $val) {
        pdebug("setting key", 10);
        $rv = ! $$dref{$db}->db_put($key, $val);

      # Or delete the key
      } else {
        pdebug("deleting key ($key)", 10);
        $rv = ! $$dref{$db}->db_del($key);
      }

      # Unlock database
      $$dref{$db}->db_sync;
      $lock->cds_unlock;
      punlock("$dbdir/db.lock");

    # Report error
    } else {
      Paranoid::ERROR = pdebug("attempted to use an " .
        "undefined key", 9);
    }

  # Report invalid database
  } else {
    Paranoid::ERROR = pdebug("attempted to access a " .
      "nonexistent database ($db)", 9);
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 getKeys

  @keys = $db->getKeys();
  @keys = $db->getKeys($dbname);

This returns all of the keys in the requested database, in hash order.

=cut

sub getKeys ($;$) {
  my $self    = shift;
  my $db      = shift;
  my $d       = defined $db  ? $db  : 'undef';
  my $dref    = $self->{Dbs};
  my $dbdir   = $self->{DbDir};
  my ($cursor, $key, $val, @keys);

  pdebug("entering w/($d)", 9);
  pIn();

  # Set the default database name if it wasn't passed
  unless (defined $db) {
    $db = $self->{DbName};
    pdebug("setting db to default ($db)", 10);
  }

  # Make sure database exists
  if (exists $$dref{$db}) {

    # Lock database for read mode
    plock("$dbdir/db.lock", 'shared');

    # Retrieve all the keys
    $key = $val = '';
    $cursor = $$dref{$db}->db_cursor;
    while ($cursor->c_get($key, $val, DB_NEXT) == 0) {
      push(@keys, $key) if defined $key };
    $cursor->c_close;

    # Unlock database
    punlock("$dbdir/db.lock");

  # Report invalid database
  } else {
    Paranoid::ERROR = pdebug("attempted to access a " .
      "nonexistent database ($db)", 9);
  }

  pOut();
  pdebug("leaving w/@{[ scalar @keys ]} keys", 9);

  return @keys;
}

=head2 purgeDb

  $db->purgeDb();
  $db->purgeDb($dbname);

This method purges all associative pairs from the designated database.  If no
database name was passed then the default database will be used.  This method
returns the number of records purged, or a -1 if an invalid database was
requested.

=cut

sub purgeDb ($;$) {
  my $self    = shift;
  my $db      = shift;
  my $d       = defined $db  ? $db  : 'undef';
  my $dref    = $self->{Dbs};
  my $dbdir   = $self->{DbDir};
  my $rv      = 0;
  my $lock;

  pdebug("entering w/($d)", 9);
  pIn();

  # Set the default database name if it wasn't passed
  unless (defined $db) {
    $db = $self->{DbName};
    pdebug("setting db to default ($db)", 10);
  }

  # Make sure database exists
  if (exists $$dref{$db}) {

    # Lock database for write mode
    plock("$dbdir/db.lock");
    $lock = $$dref{$db}->cds_lock;

    # Purge the database
    $$dref{$db}->truncate($rv);

    # Unlock database
    $$dref{$db}->db_sync;
    $lock->cds_unlock;
    punlock("$dbdir/db.lock");

  # Report invalid database
  } else {
    Paranoid::ERROR = pdebug("attempted to purge a " .
      "nonexistent database ($db)", 9);
    $rv = -1;
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 listDbs

  @dbs = $db->listDbs();

Returns a list of databases accessible by this object.

=cut

sub listDbs ($) {
  my $self    = shift;
  my $dref    = $self->{Dbs};
  my @dbs     = keys %$dref;

  pdebug("entering", 9);
  pdebug("Leaving w/rv: @dbs", 9);

  return @dbs;
}

sub DESTROY {
  my $self  = shift;
  my $dref  = $self->{Dbs};
  my $dbdir = $self->{DbDir};

  pdebug("entering", 9);
  pIn();

  # Sync & Close all dbs
  plock("$dbdir/db.lock");
  foreach (keys %$dref) {
    if (defined $$dref{$_}) {
      pdebug("sync/close $_", 10);
      $$dref{$_}->db_sync;
      $$dref{$_}->db_close;
    }
  }
  punlock("$dbdir/db.lock");

  pOut();
  pdebug("leaving", 9);
}

1;

=head1 HISTORY

None as of yet.

=head1 AUTHOR/COPYRIGHT

(c) 2005 Arthur Corliss (corliss@digitalmages.com)

=cut



