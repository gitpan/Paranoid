# Paranoid::BerkeleyDB -- BerkeleyDB concurrent-access Object
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: BerkeleyDB.pm,v 0.85 2011/12/08 07:30:26 acorliss Exp $
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
use Paranoid::Lockfile;
use BerkeleyDB;
use Carp;

($VERSION) = ( q$Revision: 0.85 $ =~ /(\d+(?:\.(\d+))+)/sm );

use constant DEF_MODE => 0700;
use constant BDB_ERR  => -1;

#####################################################################
#
# BerkeleyDB code follows
#
#####################################################################

sub _openEnv ($) {

    # Purpose:  Opens a shared environment
    # Returns:  True/False
    # Usage:    $self->_openEnv;

    my $self = shift;
    my $rv   = 0;

    pdebug( 'entering', PDLEVEL2 );
    pIn();

    if ( defined $$self{DbEnv} ) {

        # Environment is already defined
        pdebug( 'environment already created', PDLEVEL3 );
        $rv = 1;

    } else {

        # suppress BerlekelDB warnings on older version
        no strict 'subs';

        # use lockfile to avoid race conditions
        plock( "$$self{DbDir}/plock", 'write', $$self{DbMode} );

        pdebug( "creating environment in $$self{DbDir}", PDLEVEL3 );
        $$self{DbEnv} = BerkeleyDB::Env->new(
            '-Home'  => $$self{DbDir},
            '-Flags' => DB_CREATE | DB_INIT_CDB | DB_INIT_MPOOL |
                DB_CDB_ALLDB,
            '-Mode' => $$self{DbMode},
            );
        $rv = defined $$self{DbEnv};
        pdebug( "failed to open environment: $BerkeleyDB::Error", PDLEVEL1 )
            unless $rv;

        # release the lock
        punlock("$$self{DbDir}/plock");
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL2 );

    return $rv;
}

sub _openDb ($$) {

    # Purpose:  Opens a database
    # Returns:  True/False
    # Usage:    $self->_openDb('foo.db');

    my $self = shift;
    my $dbNm = shift;
    my $rv   = 0;
    my $dbh;

    pdebug( "entering w/($dbNm)", PDLEVEL2 );
    pIn();

    if ( !defined $$self{DbEnv} ) {

        # No environment available
        pdebug( 'environment not available', PDLEVEL3 );
        $rv = 0;

    } else {

        # suppress BerlekelDB warnings on older version
        no strict 'subs';

        # use lockfile to avoid race conditions
        plock( "$$self{DbDir}/plock", 'write', $$self{DbMode} );

        pdebug( "creating database $dbNm in $$self{DbDir}", PDLEVEL3 );
        $dbh = BerkeleyDB::Hash->new(
            '-Filename' => $dbNm,
            '-Env'      => $$self{DbEnv},
            '-Flags'    => DB_CREATE,
            '-Mode'     => $$self{DbMode},
            );
        $rv = defined $dbh;
        if ($rv) {
            $$self{Dbs}{$dbNm} = $dbh;
        } else {
            pdebug( "failed to open database: $BerkeleyDB::Error", PDLEVEL1 );
        }

        # release the lock
        punlock("$$self{DbDir}/plock");
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL2 );

    return $rv;
}

sub _closeDb ($$) {

    # Purpose:  Closes a database
    # Returns:  True/False
    # Usage:    $self->_closeDb('foo.db');

    my $self = shift;
    my $dbNm = shift;
    my $rv   = 1;

    pdebug( "entering w/($dbNm)", PDLEVEL2 );
    pIn();

    if ( exists $$self{Dbs}{$dbNm} and defined $$self{Dbs}{$dbNm}) {

        # use lockfile to avoid race conditions
        plock( "$$self{DbDir}/plock", 'write', $$self{DbMode} );

        # Close the database
        if ( $$self{Dbs}{$dbNm}->db_close ) {
            delete $$self{Dbs}{$dbNm};
            $rv = 1;
        } else {
            pdebug( "failed to close database $dbNm: $BerkeleyDB::Error",
                PDLEVEL1 );
        }

        # release the lock
        punlock("$$self{DbDir}/plock");

    } else {

        # Database is already gone or never was
        delete $$self{Dbs}{$dbNm};
        $rv = 1;
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL2 );

    return $rv;
}

sub _closeEnv ($) {

    # Purpose:  Closes the environment
    # Returns:  True/False
    # Usage:    $self->_closeEnv;

    my $self = shift;
    my $rv   = 0;

    pdebug( 'entering', PDLEVEL2 );
    pIn();

    if ( defined $$self{DbEnv} ) {

        # Make sure there are no databases open
        if ( scalar keys %{ $$self{Dbs} } ) {
            pdebug( 'cannot close an environment with databases open',
                PDLEVEL1 );
        } else {
            $$self{DbEnv} = undef;
            $rv = 1;
        }
    } else {
        $rv = 1;
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL2 );

    return $rv;
}

sub _closeAll ($) {

    # Purpose:  Closes all databases and environment
    # Returns:  True/False
    # Usage:    $self->_closeAll;

    my $self = shift;
    my $rv   = 1;
    my @dbs;

    pdebug( 'entering', PDLEVEL2 );
    pIn();

    # Close all the databases
    foreach ( keys %{ $$self{Dbs} } ) {
        unless ( $rv = $self->_closeDb($_) ) {
            $rv = 0;
            last;
        }
    }

    # Close the environment
    if ($rv) {
        $rv = $self->_closeEnv;
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL2 );

    return $rv;
}

sub _reopenAll ($) {

    # Purpose:  Closes and reopens all databases and environment
    # Returns:  True/False
    # Usage:    $self->_reopenAll;

    my $self = shift;
    my $rv   = 0;
    my @pkgs = qw(BerkeleyDB::Common BerkeleyDB::CDS::Lock
        BerkeleyDB::Env BerkeleyDB::Cursor);
    my ( @dbs, $fqm, $code, %crefs );

    pdebug( 'entering', PDLEVEL2 );
    pIn();

    # Get a list of open dbs
    @dbs = keys %{ $$self{Dbs} };

    {
        no strict 'refs';
        no warnings qw(redefine prototype);

        # Remove DESTROY hooks from BerkeleyDB temporarily
        foreach (@pkgs) {
            $fqm  = $_ . '::DESTROY';
            $code = *{$fqm}{CODE};
            if ( defined $code ) {
                $crefs{$fqm} = $code;
                *{$fqm} = sub { return 1 };
            }
        }

        # Close everything
        $$self{DbLock} = undef;
        foreach (@dbs) { delete $$self{Dbs}{$_} }
        $$self{DbEnv} = undef;

        # Reinstall DESTROY hooks
        foreach ( keys %crefs ) {
            *{$_} = $crefs{$_};
        }
    }

    # Reopen environment
    if ( $self->_openEnv ) {

        # Reopen all dbs
        $rv = 1;
        foreach (@dbs) {
            unless ( $self->_openDb($_) ) {
                $rv = 0;
                last;
            }
        }
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL2 );

    return $rv;
}

sub _chkPID ($) {

    # Purpose:  Checks the PID the object was created under and reopens the
    #           database & environments if needed.
    # Returns:  True or croaks.
    # Usage:    $self->_chkPID;

    my $self = shift;

    # Check PID
    if ( $$self{PID} != $$ ) {
        if ( $self->_reopenAll ) {
            $$self{DbLock} = undef;
            $$self{PID}    = $$;
        } else {
            croak 'failed to reopen databases due to forked process';
        }
    }

    return 1;
}

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
        DbMode => undef,
        DbLock => undef,
        PID    => $$,
        );
    my $dbdir = defined $args{DbDir}  ? $args{DbDir}  : 'undef';
    my $dbNm  = defined $args{DbName} ? $args{DbName} : 'undef';
    my $mode  = defined $args{DbMode} ? $args{DbMode} : DEF_MODE;
    my ( $self, @dbs, $d );

    pdebug( "entering w/DbDir => \"$dbdir\", DbName => \"$dbNm\"", PDLEVEL1 );
    pIn();

    # Bless the reference
    $self = \%init;
    bless $self, $class;

    # Populate list of dbs
    @dbs = ( defined $dbNm and ref($dbNm) eq 'ARRAY' ) ? @$dbNm : ($dbNm);

    # Set some defaults
    $$self{DbMode} = $mode;
    $$self{DbDir}  = $dbdir;

    # Make sure directory is available and writeable
    $self = undef
        unless defined $dbdir
            and length $dbdir
            and -d $dbdir
            and -w _;

    # Open database environment
    if ($self) {
        $self = undef unless $self->_openEnv;
    }

    # Open database(s)
    if ($self) {
        if ( defined $dbNm ) {
            $$self{DbName} = $dbs[0];
            foreach (@dbs) {
                unless ( defined $_ and $self->_openDb($_) ) {
                    $self = undef;
                    last;
                }
            }
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
    my $dbNm  = shift;
    my $dbdir = $$self{DbDir};
    my $n     = defined $dbNm ? $dbNm : 'undef';
    my $mode  = $$self{DbMode};
    my $rv    = 0;
    my $db;

    pdebug( "entering w/($n)", PDLEVEL1 );
    pIn();

    croak 'Mandatory first argument must be a valid filename'
        unless defined $dbNm and length $dbNm;

    $self->_chkPID;

    $rv = $self->_openDb($dbNm);

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub getVal ($$;$) {

    # Purpose:  Returns the associated value for the requested key.
    # Returns:  String if key exists, undef otherwise
    # Usage:    $db->getVal( $key );
    # Usage:    $db->getVal( $key, $dbName );

    my $self = shift;
    my $key  = shift;
    my $db   = shift;
    my $k    = defined $key ? $key : 'undef';
    my $d    = defined $db ? $db : 'undef';
    my $dref = $$self{Dbs};
    my ( $val, $v );

    pdebug( "entering w/($k)($d)", PDLEVEL1 );
    pIn();

    # Set the default database name if it wasn't passed
    unless ( defined $db ) {
        $db = $$self{DbName};
        pdebug( "setting db to default ($db)", PDLEVEL2 );
    }

    $self->_chkPID;

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

    my $self = shift;
    my $key  = shift;
    my $val  = shift;
    my $db   = shift;
    my $k    = defined $key ? $key : 'undef';
    my $v    = defined $val ? $val : 'undef';
    my $d    = defined $db ? $db : 'undef';
    my $dref = $$self{Dbs};
    my $rv   = 0;
    my $lock;

    pdebug( "entering w/($k)($v)($d)", PDLEVEL1 );
    pIn();

    # Set the default database name if it wasn't passed
    unless ( defined $db ) {
        $db = $$self{DbName};
        pdebug( "setting db to default ($db)", PDLEVEL2 );
    }

    $self->_chkPID;

    # Check the existence of the database
    if ( exists $$dref{$db} ) {

        # Use an inherited lock or get a new one
        $lock =
            defined $$self{DbLock}
            ? $$self{DbLock}
            : $$dref{$db}->cds_lock;

        # Requested database exists
        #
        # Make sure key is defined
        if ( defined $key and defined $lock ) {

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

        } else {

            # Report use of an undefined key
            Paranoid::ERROR =
                pdebug( 'attempted to use an undefined key', PDLEVEL1 );
        }

        # Unlock database
        $lock->cds_unlock unless defined $$self{DbLock};

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
    my $dref   = $$self{Dbs};
    my ( $cursor, $key, $val, @keys, $locked );

    pdebug( "entering w/($d)($s)", PDLEVEL1 );
    pIn();

    # Set the default database name if it wasn't passed
    unless ( defined $db ) {
        $db = $$self{DbName};
        pdebug( "setting db to default ($db)", PDLEVEL2 );
    }

    $self->_chkPID;

    # Make sure database exists
    if ( exists $$dref{$db} ) {

        # Create/store a global lock if a subref is passed
        # (checking to make sure we don't already have one)
        if ( defined $$self{DbLock} ) {
            $locked = 1;
        } else {
            $locked = 0;
            $$self{DbLock} = $$dref{$db}->cds_lock;
        }

        # Retrieve all the keys
        $key = $val = '';
        $cursor =
            defined $subRef
            ? $$dref{$db}->db_cursor(DB_WRITECURSOR)
            : $$dref{$db}->db_cursor;
        while ( $cursor->c_get( $key, $val, DB_NEXT ) == 0 ) {

            if ( defined $key ) {

                # The method was passed a subroutine reference, so
                # pass the db object ref and values to the sub
                &$subRef( $self, $key, $val ) if defined $subRef;

                # Save the key;
                push @keys, $key;
            }

        }
        $cursor->c_close;
        undef $cursor;

        # Close a global lock if we opened it
        unless ($locked) {
            $$self{DbLock}->cds_unlock;
            $$self{DbLock} = undef;
        }

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

    my $self = shift;
    my $db   = shift;
    my $d    = defined $db ? $db : 'undef';
    my $dref = $$self{Dbs};
    my $rv   = 0;
    my $lock;

    pdebug( "entering w/($d)", PDLEVEL1 );
    pIn();

    # Set the default database name if it wasn't passed
    unless ( defined $db ) {
        $db = $$self{DbName};
        pdebug( "setting db to default ($db)", PDLEVEL2 );
    }

    $self->_chkPID;

    # Make sure database exists
    if ( exists $$dref{$db} ) {

        # Use an inherited lock or get a new one
        $lock =
            defined $$self{DbLock}
            ? $$self{DbLock}
            : $$dref{$db}->cds_lock;

        # Purge the database
        $$dref{$db}->truncate($rv);

        # Unlock database
        $$dref{$db}->db_sync;
        $lock->cds_unlock unless defined $$self{DbLock};

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
    my $dref = $$self{Dbs};
    my @dbs  = keys %$dref;

    pdebug( 'entering',           PDLEVEL1 );
    pdebug( "Leaving w/rv: @dbs", PDLEVEL1 );

    return @dbs;
}

sub cds_lock ($) {

    # Purpose:  Places a lock on the database environment
    # Returns:  True/False
    # Usage:    $self->cds_lock;

    my $self = shift;
    my $dref = $$self{Dbs};
    my $rv   = 0;
    my $db;

    pdebug( 'entering', PDLEVEL1 );
    pIn();

    # Set the default database name if it wasn't passed
    unless ( defined $db ) {
        $db = $$self{DbName};
        pdebug( "setting db to default ($db)", PDLEVEL2 );
    }

    if ( defined $$self{DbLock} ) {

        # Already have a lock
        $rv = 1;

    } else {

        # Get a new lock
        $rv = defined( $$self{DbLock} = $$dref{$db}->cds_lock );

    }
    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub cds_unlock ($) {

    # Purpose:  Unlocks the database environment
    # Returns:  True/False
    # Usage:    $self->cds_unlock;

    my $self = shift;
    my $rv   = 0;

    pdebug( 'entering', PDLEVEL1 );
    pIn();

    # Remove the lock
    if ( defined $$self{DbLock} ) {
        $$self{DbLock}->cds_unlock;
        $$self{DbLock} = undef;
    }
    $rv = 1;

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub DESTROY {
    my $self  = shift;
    my $dref  = $$self{Dbs};
    my $dbdir = $$self{DbDir};

    pdebug( 'entering', PDLEVEL1 );
    pIn();

    # Release any locks
    if ( defined $$self{DbLock} ) {
        $$self{DbLock}->cds_unlock;
        $$self{DbLock} = undef;
    }

    # Sync & Close all dbs
    $self->_closeAll;

    pOut();
    pdebug( 'leaving', PDLEVEL1 );

    return 1;
}

1;

__END__

=head1 NAME

Paranoid::BerkeleyDB -- BerkeleyDB CDS Object

=head1 VERSION

$Id: BerkeleyDB.pm,v 0.85 2011/12/08 07:30:26 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::BerkeleyDB;

  $db = Paranoid::BerkeleyDB->new(DbDir => '/tmp', DbName => 'foo.db', 
                                  DbMode => 0640);
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

  $db->cds_lock;
  $db->cds_unlock;

  # Close environment & databases
  $db = undef;

=head1 DESCRIPTION

This provides a OO-based wrapper for BerkeleyDB that creates Concurrent Data
Store (CDS) databases.  This is a feature of Berkeley DB v3.x and higher that
provides for concurrent use of Berkeley DBs.  It provides for multiple reader,
single writer locking, and multiple databases can share the same environment.

This module hides much of the complexity of the API (as provided by the
L<BerkeleyDB(3)> module.  Conversely, it also severely limits the options and
flexibility of the module and libraries as well.  In short, if you want a
quick and easy way for local processes to have concurrent access to Berkeley
DBs without learning bdb internals, this is your module.  If you want full
access to all of the bdb features and tuning/scalability features, you'd
better learn dbd.

One particulary nice feature of this module, however, is that it's fork-safe.
That means you can open a CDS db in a parent process, fork, and continue r/w
operations without fear of corruption or lock contention due to stale
filehandles.

B<lock> and B<unlock> methods are also provided to allow mass changes as an
atomic operation.  Since the environment is always created with a single
global write lock (regardless of how many databases exist within the
environment) operations can be made on multiple databases.

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

    &$subRef($dbObj, $key, $value);

with $dbObj being a handle to the current database object.  You may
use this ref to make changes to the database.  Anytime a code
reference is handed to this method it is automatically opened with a write
lock under the assumption that this might be a transformative operation.

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

=head2 cds_lock

    $db->cds_lock;

This method places a global write lock on the shared database environment.
Since environments are created with a global lock (covering all databases in
the environment) no writes or reads can be done by other processes until this
is unlocked.

=head2 cds_unlock

    $db->cds_unlock;

This method removes a global write lock on the shared database environment.

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

Race conditions, particularly on database creation/opens, are worked around by
the use of external lock files and B<flock> advisory file locks.  Lockfiles
are not used during normal operations on the database.

While CDS allows for safe concurrent use of database files, it makes no
allowances for recovery from stale locks.  If a process exits badly and fails
to release a write lock (which causes all other process operations to block
indefinitely) you have to intervene manually.  The brute force intervention
would mean killing all accessing processes and deleting the environment files
(files in the same directory call __db.*).  Those will be recreated by the
next process to access them.

Berkeley DB provides a handy CLI utility called L<db_stat(1)>.  It can provide
some statistics on your shared database environment via invocation like so:

  db_stat -m -h .

The last argument, of course, is the directory in which the environment was
created.  The example above would work fine if your working directory was that
directory.

You can also show all existing locks via:

    db_stat -N -Co -h .

=head1 SEE ALSO

    L<BerkeleyDB(3)>

=head1 HISTORY

2011/12/06:  Added fork-safe operation

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

