# Paranoid::BerkeleyDB -- BerkeleyDB concurrent-access Object
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: BerkeleyDB.pm,v 0.6 2009/03/04 09:32:51 acorliss Exp $
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
use Paranoid::Lockfile;
use Paranoid::Filesystem qw(pmkdir);
use BerkeleyDB;
use Carp;

($VERSION) = ( q$Revision: 0.6 $ =~ /(\d+(?:\.(\d+))+)/sm );

#####################################################################
#
# BerkeleyDB code follows
#
#####################################################################

sub new (@) {
    my $class = shift;
    my %args  = @_;
    my %init  = (
        DbDir  => undef,
        DbName => undef,
        Dbs    => {},
        DbEnv  => undef,
    );
    my $dbdir = defined $args{DbDir}  ? $args{DbDir}  : 'undef';
    my $dbnm  = defined $args{DbName} ? $args{DbName} : 'undef';
    my ( $self, $tmp );

    pdebug( "entering w/DbDir => \"$dbdir\", DbName => \"$dbnm\"", PDLEVEL1 );
    pIn();

    # Make sure $dbdir & $dbnm are defined and BerkeleyDB is available
    if ( defined $dbdir and defined $dbnm ) {

        # Create the directory (and let umask determine the permissions)
        if ( pmkdir( $dbdir, 0777 ) ) {

            # Create lock file and lock it while doing initialization.  I
            # know, this isn't ideal when creating temporary objects that
            # need only read access, but it's the only way to avoid race
            # conditions if this is the process that creates the database.
            plock( "$dbdir/db.lock", undef, 0666 );

            # Create and bless the object reference
            @init{qw(DbDir DbName)} = ( $dbdir, $dbnm );
            $self = \%init;
            bless $self, $class;

            # Initialize the environment
            no strict 'subs';

            # Check creation of db env
            if (defined(
                    $tmp = BerkeleyDB::Env->new(
                        '-Home'    => $dbdir,
                        '-ErrFile' => \*STDERR,
                        '-Flags'   => DB_CREATE | DB_INIT_CDB | DB_INIT_MPOOL,
                    ) )
                ) {

                # Success! Now, create the database
                $self->{DbEnv} = $tmp;
                $tmp = BerkeleyDB::Hash->new(
                    '-Filename' => $dbnm,
                    '-Env'      => $self->{DbEnv},
                    '-Flags'    => DB_CREATE,
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
            punlock("$dbdir/db.lock");

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
    my $self  = shift;
    my $dbnm  = shift;
    my $dbdir = $self->{DbDir};
    my $n     = defined $dbnm ? $dbnm : 'undef';
    my $rv    = 0;
    my $db;

    pdebug( "entering w/($n)", PDLEVEL1 );
    pIn();

    # Make sure a valid name was passed and it hasn't already been created
    if ( defined $dbnm and not exists ${ $self->{Dbs} }{$dbnm} ) {

        # Get exclusive lock
        plock("$dbdir/db.lock");

        $db = BerkeleyDB::Hash->new(
            '-Filename' => $dbnm,
            '-Env'      => $self->{DbEnv},
            '-Flags'    => DB_CREATE,
        );

        # Store & report the result
        $rv = defined $db ? 1 : 0;
        if ($rv) {
            $self->{Dbs}->{$dbnm} = $db;
            pdebug( "added new database: $dbnm", PDLEVEL2 );
        } else {
            Paranoid::ERROR =
                pdebug( "failed to add new database: $dbnm", PDLEVEL1 );
        }

        # Release lock
        punlock("$dbdir/db.lock");
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub getVal ($$;$) {
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

        # Requested database exists
        #
        # Lock database for read mode
        plock( "$dbdir/db.lock", 'shared' );

        unless ( $$dref{$db}->db_get( $key, $val ) == 0 ) {
            pdebug( "no such key exists ($key)", PDLEVEL2 );
        }

        # Unlock database
        punlock("$dbdir/db.lock");

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
        if ( defined $key ) {

            # Lock database for write mode
            plock("$dbdir/db.lock");
            $lock = $$dref{$db}->cds_lock;

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
            punlock("$dbdir/db.lock");

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

sub getKeys ($;$) {
    my $self  = shift;
    my $db    = shift;
    my $d     = defined $db ? $db : 'undef';
    my $dref  = $self->{Dbs};
    my $dbdir = $self->{DbDir};
    my ( $cursor, $key, $val, @keys );

    pdebug( "entering w/($d)", PDLEVEL1 );
    pIn();

    # Set the default database name if it wasn't passed
    unless ( defined $db ) {
        $db = $self->{DbName};
        pdebug( "setting db to default ($db)", PDLEVEL2 );
    }

    # Make sure database exists
    if ( exists $$dref{$db} ) {

        # Lock database for read mode
        plock( "$dbdir/db.lock", 'shared' );

        # Retrieve all the keys
        $key = $val = '';
        $cursor = $$dref{$db}->db_cursor;
        while ( $cursor->c_get( $key, $val, DB_NEXT ) == 0 ) {
            push @keys, $key if defined $key;
        }
        $cursor->c_close;

        # Unlock database
        punlock("$dbdir/db.lock");

        # Report invalid database
    } else {
        Paranoid::ERROR =
            pdebug( "attempted to access a nonexistent database ($db)",
            PDLEVEL1 );
    }

    pOut();
    pdebug( "leaving w/@{[ scalar @keys ]} keys", PDLEVEL1 );

    return @keys;
}

sub purgeDb ($;$) {
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
        Paranoid::ERROR =
            pdebug( "attempted to purge a nonexistent database ($db)",
            PDLEVEL1 );
        $rv = -1;
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub listDbs ($) {
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
    plock("$dbdir/db.lock");
    foreach ( keys %$dref ) {
        if ( defined $$dref{$_} ) {
            pdebug( "sync/close $_", PDLEVEL2 );
            $$dref{$_}->db_sync;
            $$dref{$_}->db_close;
            delete $$dref{$_};
        }
    }

    # Release the locks
    punlock("$dbdir/db.lock");
    pcloseLockfile("$dbdir/db.lock");

    pOut();
    pdebug( 'leaving', PDLEVEL1 );

    return 1;
}

1;

__END__

=head1 NAME

Paranoid::BerkeleyDB -- BerkeleyDB concurrent-access Object

=head1 VERSION

$Id: BerkeleyDB.pm,v 0.6 2009/03/04 09:32:51 acorliss Exp $

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

This method returns all of the keys in the requested database, in hash order.

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

