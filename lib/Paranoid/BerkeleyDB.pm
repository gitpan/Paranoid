# Paranoid::BerkeleyDB -- BerkeleyDB concurrent-access Object
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: BerkeleyDB.pm,v 0.84 2011/08/18 06:55:27 acorliss Exp $
#
#    This software is licensed under the same terms as Perl, itself.
#    Please see http://dev.perl.org/licenses/ for more information.
#
#####################################################################

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
use Paranoid::Debug qw(:all);
use Paranoid::Filesystem qw(pmkdir);
use BerkeleyDB;
use Carp;
use Fcntl qw(:flock O_RDWR O_CREAT O_EXCL);

($VERSION) = ( q$Revision: 0.84 $ =~ /(\d+(?:\.(\d+))+)/sm );

use constant DEF_MODE => 0700;
use constant BDB_ERR  => -1;

#####################################################################
#
# BerkeleyDB code follows
#
#####################################################################

sub new (@) {

    # Purpose:  Instantiates a new object of this class
    # Returns:  Object reference if successful, undef otherwise
    # Usage:    $obj = Paranoid::BerkeleyDB->new(
    #                   DbDir   = $dir,
    #                   DbName  = $name,
    #                   );

    my ( $class, %args ) = @_;
    my %init = (
        DbDir  => undef,
        DbName => undef,
        Dbs    => {},
        DbEnv  => undef,
        DbLock => undef,
        DbMode => undef,
        );
    my $dbdir = defined $args{DbDir}  ? $args{DbDir}  : 'undef';
    my $dbnm  = defined $args{DbName} ? $args{DbName} : 'undef';
    my $mode  = defined $args{DbMode} ? $args{DbMode} : DEF_MODE;
    my ( $self, $tmp, $lfh, $rv );

    pdebug( "entering w/DbDir => \"$dbdir\", DbName => \"$dbnm\"", PDLEVEL1 );
    pIn();

    # Make sure $dbdir & $dbnm are defined and BerkeleyDB is available
    if ( defined $dbdir and defined $dbnm ) {

        # Create the directory (and let umask determine the permissions)
        if ( pmkdir( $dbdir, $mode ) ) {

            # Create lock file and lock it while doing initialization.  I
            # know, this isn't ideal when creating temporary objects that
            # need only read access, but it's the only way to avoid race
            # conditions if this is the process that creates the database.
            if ( sysopen $lfh, "$dbdir/db.lock", O_RDWR | O_CREAT | O_EXCL,
                $mode ) {
                $rv = flock $lfh, LOCK_EX;
            } elsif ( sysopen $lfh, "$dbdir/db.lock", O_RDWR, $mode ) {
                $rv = flock $lfh, LOCK_SH;
            }
            unless ($rv) {
                pOut();
                pdebug( 'leaving w/rv: undef', PDLEVEL1 );
            }

            # Create and bless the object reference
            @init{qw(DbDir DbName DbLock DbMode)} =
                ( $dbdir, $dbnm, $lfh, $mode );
            $self = \%init;
            bless $self, $class;

            # Initialize the environment
            no strict 'subs';

            # Check creation of db env
            if (defined(
                    $tmp = BerkeleyDB::Env->new(
                        '-Home'    => $dbdir,
                        '-ErrFile' => \*STDERR,
                        '-Flags' => DB_CREATE | DB_INIT_CDB | DB_INIT_MPOOL |
                            DB_CDB_ALLDB,
                        '-Mode' => $mode,
                        ) )
                ) {

                # Success! Now, create the database
                $self->{DbEnv} = $tmp;
                $tmp = BerkeleyDB::Hash->new(
                    '-Filename' => $dbnm,
                    '-Env'      => $self->{DbEnv},
                    '-Flags'    => DB_CREATE,
                    '-Mode'     => $mode,
                    );

                # Check if creating the db was successful
                if ( defined $tmp ) {

                    # Success!
                    $self->{Dbs}->{$dbnm} = $tmp;

                } else {

                    # Abysmal failure!
                    $self = undef;
                    Paranoid::ERROR =
                        pdebug( "failed to create BerkeleyDB $dbnm: $!",
                        PDLEVEL1 );
                }

            } else {

                # Abject failure!
                $self = undef;
                Paranoid::ERROR =
                    pdebug( "failed to initialize BerkeleyDB Env: $!",
                    PDLEVEL1 );
            }

            # Unlock the database
            flock $lfh, LOCK_UN;

        } else {

            # Failed to create the db directory
            Paranoid::ERROR = pdebug(
                "failed to create directory $dbdir: @{[ Paranoid::ERROR ]}",
                PDLEVEL1 );
        }
    }

    pOut();
    pdebug( 'leaving w/rv: ' . ( defined $self ? $self : 'undef' ),
        PDLEVEL1 );

    return $self;
}

sub addDb ($$) {

    # Purpose:  Adds a new named database to the current environment
    # Returns:  True/false
    # Usage:    $rv = $db->addDb( 'foo.db' );

    my $self  = shift;
    my $dbnm  = shift;
    my $dbdir = $self->{DbDir};
    my $n     = defined $dbnm ? $dbnm : 'undef';
    my $mode  = $self->{DbMode};
    my $rv    = 0;
    my $db;

    pdebug( "entering w/($n)", PDLEVEL1 );
    pIn();

    # Make sure a valid name was passed and it hasn't already been created
    if ( defined $dbnm and not exists ${ $self->{Dbs} }{$dbnm} ) {

        # Get exclusive lock
        flock $$self{DbLock}, LOCK_EX;

        $db = BerkeleyDB::Hash->new(
            '-Filename' => $dbnm,
            '-Env'      => $self->{DbEnv},
            '-Flags'    => DB_CREATE,
            '-Mode'     => $mode,
            );

        # Release lock
        flock $$self{DbLock}, LOCK_UN;

        # Store & report the result
        $rv = defined $db ? 1 : 0;
        if ($rv) {
            $self->{Dbs}->{$dbnm} = $db;
            pdebug( "added new database: $dbnm", PDLEVEL2 );
        } else {
            Paranoid::ERROR =
                pdebug( "failed to add new database: $dbnm", PDLEVEL1 );
        }
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub getVal ($$;$) {

    # Purpose:  Returns the associated value for the requested key.
    # Returns:  String if key exists, undef otherwise
    # Usage:    $db->getVal( $key );
    # Usage:    $db->getVal( $key, $dbName );

    my $self  = shift;
    my $key   = shift;
    my $db    = shift;
    my $k     = defined $key ? $key : 'undef';
    my $d     = defined $db ? $db : 'undef';
    my $dref  = $self->{Dbs};
    my $dbdir = $self->{DbDir};
    my ( $val, $v );

    pdebug( "entering w/($k)($d)", PDLEVEL1 );
    pIn();

    # Set the default database name if it wasn't passed
    unless ( defined $db ) {
        $db = $self->{DbName};
        pdebug( "setting db to default ($db)", PDLEVEL2 );
    }

    # Check the existence of the database
    if ( exists $$dref{$db} ) {

        unless ( $$dref{$db}->db_get( $key, $val ) == 0 ) {
            pdebug( "no such key exists ($key)", PDLEVEL2 );
        }

    } else {

        # Report invalid database
        Paranoid::ERROR =
            pdebug( "attempted to access a nonexistent database ($db)",
            PDLEVEL1 );
    }

    $v = defined $val ? $val : 'undef';
    pOut();
    pdebug( "leaving w/rv: $v", PDLEVEL1 );

    return $val;
}

sub setVal ($$;$$) {

    # Purpose:  Associates the key with the passed value or, if the
    #           value is undefined, deletes any existing key.
    # Returns:  True/false
    # Usage:    $db->setVal( $key, $value );
    # Usage:    $db->setVal( $key, $value, $dbName );

    my $self  = shift;
    my $key   = shift;
    my $val   = shift;
    my $db    = shift;
    my $k     = defined $key ? $key : 'undef';
    my $v     = defined $val ? $val : 'undef';
    my $d     = defined $db ? $db : 'undef';
    my $dref  = $self->{Dbs};
    my $dbdir = $self->{DbDir};
    my $rv    = 0;
    my $lock;

    pdebug( "entering w/($k)($v)($d)", PDLEVEL1 );
    pIn();

    # Set the default database name if it wasn't passed
    unless ( defined $db ) {
        $db = $self->{DbName};
        pdebug( "setting db to default ($db)", PDLEVEL2 );
    }

    # Check the existence of the database
    if ( exists $$dref{$db} ) {

        # Requested database exists
        #
        # Make sure key is defined
        if ( defined $key and defined( $lock = $$dref{$db}->cds_lock ) ) {

            # Check whether setting a new record or deleting one
            if ( defined $val ) {

                # Setting a new record
                pdebug( "setting key $key to $val", PDLEVEL2 );
                $rv = !$$dref{$db}->db_put( $key, $val );

            } else {

                # Deleting the record
                pdebug( "deleting key ($key)", PDLEVEL2 );
                $rv = !$$dref{$db}->db_del($key);
            }

            # Unlock database
            $$dref{$db}->db_sync;
            $lock->cds_unlock;

        } else {

            # Report use of an undefined key
            Paranoid::ERROR =
                pdebug( 'attempted to use an undefined key', PDLEVEL1 );
        }

    } else {

        # Report invalid database
        Paranoid::ERROR =
            pdebug( "attempted to access a nonexistent database ($db)",
            PDLEVEL1 );
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub getKeys ($;$$) {

    # Purpose:  Returns a list of all the keys in the database and
    #           optionally runs a subroutine over each record.
    # Returns:  List of keys.
    # Usage:    @keys = $db->getKeys;
    # Usage:    @keys = $db->getKeys( $dbName );
    # Usage:    @keys = $db->getKeys( $dbName, undef );

    my $self   = shift;
    my $db     = shift;
    my $subRef = shift;
    my $d      = defined $db ? $db : 'undef';
    my $s      = defined $subRef ? $subRef : 'undef';
    my $dref   = $self->{Dbs};
    my $dbdir  = $self->{DbDir};
    my ( $cursor, $key, $val, @keys );

    pdebug( "entering w/($d)($s)", PDLEVEL1 );
    pIn();

    # Set the default database name if it wasn't passed
    unless ( defined $db ) {
        $db = $self->{DbName};
        pdebug( "setting db to default ($db)", PDLEVEL2 );
    }

    # Make sure database exists
    if ( exists $$dref{$db} ) {

        # Retrieve all the keys
        $key = $val = '';
        $cursor =
            defined $subRef
            ? $$dref{$db}->db_cursor(DB_WRITECURSOR)
            : $$dref{$db}->db_cursor;
        while ( $cursor->c_get( $key, $val, DB_NEXT ) == 0 ) {

            if ( defined $key ) {

                # The method was passed a subroutine reference, so
                # unlock the database and call the routine
                &$subRef( $self, $key, $val ) if defined $subRef;

                # Save the key;
                push @keys, $key;
            }

        }
        $cursor->c_close;
        undef $cursor;

    } else {

        # Report invalid database
        Paranoid::ERROR =
            pdebug( "attempted to access a nonexistent database ($db)",
            PDLEVEL1 );
    }

    pOut();
    pdebug( "leaving w/@{[ scalar @keys ]} keys", PDLEVEL1 );

    return @keys;
}

sub purgeDb ($;$) {

    # Purpose:  Empties the database.
    # Returns:  True/false
    # Usage:    $rv = $db->purgeDb;
    # Usage:    $rv = $db->purgeDb( $dbName );

    my $self  = shift;
    my $db    = shift;
    my $d     = defined $db ? $db : 'undef';
    my $dref  = $self->{Dbs};
    my $dbdir = $self->{DbDir};
    my $rv    = 0;
    my $lock;

    pdebug( "entering w/($d)", PDLEVEL1 );
    pIn();

    # Set the default database name if it wasn't passed
    unless ( defined $db ) {
        $db = $self->{DbName};
        pdebug( "setting db to default ($db)", PDLEVEL2 );
    }

    # Make sure database exists
    if ( exists $$dref{$db} ) {

        # Lock database for write mode
        flock $$self{DbLock}, LOCK_EX;
        $lock = $$dref{$db}->cds_lock;

        # Purge the database
        $$dref{$db}->truncate($rv);

        # Unlock database
        $$dref{$db}->db_sync;
        $lock->cds_unlock;
        flock $$self{DbLock}, LOCK_UN;

    } else {

        # Report invalid database
        Paranoid::ERROR =
            pdebug( "attempted to purge a nonexistent database ($db)",
            PDLEVEL1 );
        $rv = BDB_ERR;
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub listDbs ($) {

    # Purpose:  Returns a list of all named database
    # Returns:  List of database names
    # Usage:    @dbs = $db->listDbs;

    my $self = shift;
    my $dref = $self->{Dbs};
    my @dbs  = keys %$dref;

    pdebug( 'entering',           PDLEVEL1 );
    pdebug( "Leaving w/rv: @dbs", PDLEVEL1 );

    return @dbs;
}

sub DESTROY {
    my $self  = shift;
    my $dref  = $self->{Dbs};
    my $dbdir = $self->{DbDir};

    pdebug( 'entering', PDLEVEL1 );
    pIn();

    # Sync & Close all dbs
    flock $$self{DbLock}, LOCK_EX;
    foreach ( keys %$dref ) {
        if ( defined $$dref{$_} ) {
            pdebug( "sync/close $_", PDLEVEL2 );
            $$dref{$_}->db_close;
            delete $$dref{$_};
        }
    }

    # Release the locks
    flock $$self{DbLock}, LOCK_UN;

    pOut();
    pdebug( 'leaving', PDLEVEL1 );

    return 1;
}

1;

__END__

=head1 NAME

Paranoid::BerkeleyDB -- BerkeleyDB concurrent-access Object

=head1 VERSION

$Id: BerkeleyDB.pm,v 0.84 2011/08/18 06:55:27 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::BerkeleyDB;

  $db = Paranoid::BerkeleyDB->new(DbDir => '/tmp', DbName => 'foo.db', 
                                  DbMode => 0770);
  $rv = $db->addDb($dbname);

  $val = $db->getVal($key);
  $val = $db->getVal($key, $dbname);

  $rv = $db->setVal($key, $val);
  $rv = $db->setVal($key, $val, $dbname);

  @keys = $db->getKeys();
  @keys = $db->getKeys($dbname);
  @keys = $db->getKeys(undef, \&sub);
  @keys = $db->getKeys($dbname, \&sub);

  $db->purgeDb();
  $db->purgeDb($dbname);

  @dbs = $db->listDbs();

  # Close environment & databases
  $db = undef;

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

Limitations:  all keys and all values must be valid strings.  That means that
attempting to set a valid key's associated value to B<undef> will fail to add
that key to the database.  In fact, if the an existing key is assigned a
undefined value it will be deleted from the database.

B<NOTE> Many versions of BerkeleyDB liberaries that provide concurrent access
are buggy as all hell.  I can vouch that as of 4.6.21 most of those problems
have gone away.  In a nutshell, if you get errors about running out of
lockers the problem is likely in the db libraries themselves, not in this
module.

=head1 SUBROUTINES/METHODS

=head2 new

  $db = Paranoid::BerkeleyDB->new(DbDir => '/tmp', DbName => 'foo.db');

This class method is the object instantiator.  Two arguments are required:  
B<DbDir> which is the path to the directory where the database files will be 
stored, and B<DbName> which is the filename of the database itself.  If 
B<DbDir> doesn't exist it will be created for you automatically.

B<DbMode> is optional, and if omitted defaults to 0700.  This affects the
database directory, files, and lockfile.

This method will create a BerkeleyDB Environment and will support 
multiprocess transactions.

Any errors in the operation will be stored in B<Paranoid::ERROR>.

=head2 addDb

  $rv = $db->addDb($dbname);

This method adds another database to the current object and environment.  
Calling this method does require an exclusive write lock to the database 
to prevent race conditions.

Any errors in the operation will be stored in B<Paranoid::ERROR>.

=head2 getVal

  $val = $db->getVal($key);
  $val = $db->getVal($key, $dbname);

This method retrieves the associated string to the passed key.  Called with 
one argument the method uses the default database.  Otherwise, a second 
argument specifying the specific database is required.

Requesting a non-existent key or from a nonexistent database will result in 
an undef being returned.  In the case of the latter an error message will also
be set in B<Paranoid::ERROR>.

=head2 setVal

  $rv = $db->setVal($key, $val);
  $rv = $db->setVal($key, $val, $dbname);

This method adds or updates an associative pair.  If the passed value is
B<undef> the key is deleted from the database.  If no database is explicitly
named it is assumed that the default database is the one to work on.

Requesting a non-existent key or from a nonexistent database will result in 
an undef being returned.  In the case of the latter an error message will also
be set in B<Paranoid::ERROR>.

=head2 getKeys

  @keys = $db->getKeys();
  @keys = $db->getKeys($dbname);
  @keys = $db->getKeys(undef, \&sub);
  @keys = $db->getKeys($dbname, \&sub);

If this method is called without the optional subroutine reference it will
return all the keys in the hash in hash order.  If a subroutine reference is
called it will be called as each key/value pair is iterated over with three
arguments:

    &$subRef($self, $key, $value);

with $self being a handle to the current Paranoid::BerkeleyDB object.  You may
use this object handle to perform other database operations as needed.

=head2 purgeDb

  $db->purgeDb();
  $db->purgeDb($dbname);

This method purges all associative pairs from the designated database.  If no
database name was passed then the default database will be used.  This method
returns the number of records purged, or a -1 if an invalid database was
requested.

=head2 listDbs

  @dbs = $db->listDbs();

This method returns a list of databases accessible by this object.

=head2 DESTROY

A DESTROY method is provided which should sync and close an open database, as
well as release any locks.

=head1 DEPENDENCIES

=over

=item o

L<Paranoid>

=item o

L<Paranoid::Debug>

=item o

L<Paranoid::Filesystem>

=item o

L<Paranoid::Lockfile>

=item o

L<BerkeleyDB>

=back

=head1 BUGS AND LIMITATIONS

Due to the excessive reliance on lockfiles meant to prevent race conditions
with other processes, this won't be the fastest db access if you're rapidly
creating, destroying, and re-creating objects.  If you're keeping an object
around for extended use it should be reasonable.

If you have multiple dbs accessible via one object (and environment) you do
need to remember that there is only one global write lock per environment.
So, even if other processes need to access a different db that what is being
written to, they'll have to wait until the write lock is released.

Finally, no provisions have been made to allow tuning of the BerkeleyDB
environment.  If the defaults don't work well for your workloads don't use
this module.

End sum:  this module should be safe and reliable, but not necessarily
high-performing, especially with workloads with a high write-to-read
transaction ratio.

=head1 HISTORY

None as of yet.

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

