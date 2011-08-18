# Paranoid::Lockfile -- Paranoid Lockfile support
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Lockfile.pm,v 0.63 2011/08/18 06:54:32 acorliss Exp $
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

package Paranoid::Lockfile;

use 5.006;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS);
use base qw(Exporter);
use Fcntl qw(:flock O_RDWR O_CREAT O_EXCL);
use Paranoid;
use Paranoid::Debug qw(:all);
use Paranoid::Filesystem;
use Carp;

($VERSION) = ( q$Revision: 0.63 $ =~ /(\d+(?:\.(\d+))+)/sm );

@EXPORT      = qw(plock punlock pcloseLockfile);
@EXPORT_OK   = qw(plock punlock pcloseLockfile);
%EXPORT_TAGS = ( all => [qw(plock punlock pcloseLockfile)], );

use constant PRIV_UMASK => 0600;

#####################################################################
#
# Module code follows
#
#####################################################################

{

    # file descriptor stash
    my %fd;

    sub _clearLocks {

        # Purpose:  Cleanly closes all lockfiles
        # Returns:  True/false
        # Usage:    $rv = _clearLocks();

        my ( $frv, $rv );

        pdebug( 'entering', PDLEVEL2 );
        pIn();

        $frv = 1;
        foreach ( keys %fd ) {
            $rv = pcloseLockfile($_);
            $frv = 0 unless $rv;
            pdebug( "$_ rv: $rv", PDLEVEL3 );
        }

        pOut();
        pdebug( "leaving w/rv: $frv", PDLEVEL2 );

        return $frv;
    }

    sub plock ($;$$) {

        # Purpose:  Opens and locks the specified file.
        # Returns:  True/false
        # Usage:    $rv = plock( $filename );
        # Usage:    $rv = plock( $filename, $lockType, $fileMode );

        my $filename = shift;
        my $type     = shift;
        my $mode     = shift;
        my $targ     = defined $type ? $type : 'undef';
        my $marg     = defined $mode ? $mode : 'undef';
        my $rv       = 0;
        my ( $fd, $irv );

        # Validate arguments
        croak 'Mandatory first argument must be a defined filename'
            unless defined $filename && length $filename > 0;
        croak 'Optional second argument must be a valid lock type'
            unless !defined $type
                || ( defined $type && $type =~ /^(?:write|shared)$/sm );

        pdebug( "entering w/($filename)($targ)($marg)", PDLEVEL1 );
        pIn();

        # Get the filehandle
        if ( exists $fd{$filename} ) {

            # Retrieve a previously stored filehandle
            $fd = $fd{$filename};

        } else {

            # Open a new filehandle
            #
            # Set the default perms if needed
            $mode = PRIV_UMASK unless defined $mode;

            # To avoid race conditions with multiple files opening (and
            # overwriting) the same file, and hence doing flocks on
            # descriptors with a different # (f#*&ing lock isn't working!)
            # we attempt to do an exclusive open first.  If that fails, then
            # we do reopen to get a filehandle to the (possibly) newly
            # created file.
            $irv = sysopen( $fd, $filename, O_RDWR | O_CREAT | O_EXCL, $mode )
                || sysopen( $fd, $filename, O_RDWR );

            # Store the new filehandle
            $fd{$filename} = $fd if $irv;
        }

        # Flock it
        if ($irv) {

            # Assign the lock type according to $type
            $type = 'write' unless defined $type;
            $type = $type eq 'write' ? LOCK_EX : LOCK_SH;
            $rv = flock $fd, $type;
        }

        pOut();
        pdebug( "leaving w/rv: $rv", PDLEVEL1 );

        return $rv;
    }

    sub punlock ($) {

        # Purpose:  Removes any existing locks on the file
        # Returns:  True/false
        # Usage:    $rv = punlock();

        my $filename = shift;
        my $rv       = 1;

        # Validate arguments
        croak 'Mandatory first argument must be a defined filename'
            unless defined $filename && length $filename > 0;

        pdebug( "entering w/($filename)", PDLEVEL1 );
        pIn();

        $rv = flock $fd{$filename}, LOCK_UN if exists $fd{$filename};

        pOut();
        pdebug( "leaving w/rv: $rv", PDLEVEL1 );

        return $rv;
    }

    sub pcloseLockfile ($) {

        # Purpose:  Unlocks and closes the passed filename
        # Returns:  True/false
        # Usage:    $rv = pcloseLockfile( $filename );

        my $filename = shift;
        my $rv       = 1;

        # Validate arguments
        croak 'Mandatory first argument must be a defined filename'
            unless defined $filename && length $filename > 0;

        pdebug( "entering w/($filename)", PDLEVEL1 );
        pIn();

        if ( exists $fd{$filename} ) {
            $rv = flock( $fd{$filename}, LOCK_UN )
                and close $fd{$filename};
            delete $fd{$filename} if $rv;
        }

        pOut();
        pdebug( "leaving w/rv: $rv", PDLEVEL1 );

        return $rv;
    }
}

END {
    _clearLocks();
}

1;

__END__

=head1 NAME

Paranoid::Lockfile - Paranoid Lockfile support

=head1 VERSION

$Id: Lockfile.pm,v 0.63 2011/08/18 06:54:32 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Lockfile;

  $rv = plock($lockfile);
  $rv = punlock($lockfile);
  $rv = pcloseLockfile($lockfile);

=head1 DESCRIPTION

This modules provides a relatively safe locking mechanism multiple processes.
This does not work over NFS or across remote systems, this is only intended
for use on a single system at a time, and only on those that support B<flock>.

B<sysopen> is used to avoid race conditions with multiple process attempting
to create the same file simultaneously.

=head1 SUBROUTINES/METHODS

=head2 plock

  $rv = plock($filename);

This function attempts to safely create or open the lockfile.  It uses
B<sysopen> with B<O_CREAT | O_EXCL> to avoid race conditions with other
processes.  Returns a true if successful.

Your can pass an optional second argument which would be a string of either
'write' or 'shared'.  The default is 'write', which locks the file in
exclusive write mode.

You can pass an optional third argument which would be the lockfile
filesystem permissions if the file is created.  The default is 0600.

B<NOTE:> This function will block until the advisory lock is granted.

=head2 punlock

  $rv = punlock($filename);

This function removes any existing locks on the specified filename using
B<flock>.  If no previous lock existed or it was successful it returns true.
This does not, however, close the open filehandle to the lockfile.

=head2 pcloseLockfile

  $rv = pcloseLockfile($filename);

This function releases any existing locks and closes the open filehandle to
the lockfile.  Returns true if the file isn't currently open or the operation
succeeds.

=head1 DEPENDENCIES

=over

=item o

L<Fcntl>

=item o

L<Paranoid>

=item o

L<Paranoid::Debug>

=back

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

