# Paranoid::Log::File -- File Log support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: File.pm,v 0.83 2010/04/15 23:23:28 acorliss Exp $
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

package Paranoid::Log::File;

use 5.006;

use strict;
use warnings;
use vars qw($VERSION);
use Paranoid::Debug qw(:all);
use Paranoid::Filesystem;
use Paranoid::Input;
use Carp;
use Fcntl qw(:flock :seek O_WRONLY O_CREAT O_APPEND);

($VERSION) = ( q$Revision: 0.83 $ =~ /(\d+(?:\.(\d+))+)/sm );

#####################################################################
#
# Module code follows
#
#####################################################################

{

    my %fhandles;
    my %fpids;

    sub _delHandle {

        # Purpose:  closes any opened filehandles and cleans up the internal
        #           data structures
        # Returns:  Result of close(), or True (1) if no such file opened
        # Usage:    $rv = _delHandle($filename);

        my $filename = shift;
        my $rv       = 1;

        if ( exists $fhandles{$filename} && $fpids{$filename} == $$ ) {
            $rv = close $fhandles{$filename};
            delete $fhandles{$filename};
            delete $fpids{$filename};
        }

        return $rv;
    }

    sub _getHandle {

        # Purpose:  Retrieves a filehandle to the requested file.  It will
        #           automatically create the file if necessary.  It also
        #           tracks what process opened the filehandle so a new one is
        #           opened after a fork call.
        # Returns:  Filehandle
        # Usage:    $fh = _getHandle($filename);

        my $filename = shift;
        my ( $f, $fd, $rv );

        # Is there a filehandle cached?
        if ( exists $fhandles{$filename} ) {

            # Yes, so was it opened by us?
            if ( $fpids{$filename} == $$ ) {

                # Yup, return the filehandle
                $rv = $fhandles{$filename};

            } else {

                # Nope, let's delete it and reopen it
                delete $fhandles{$filename};
                $rv = _getHandle($filename);
            }

        } else {

            # Nope, let's open it up if we can detaint the filename
            if ( detaint( $filename, 'filename', \$f ) ) {

                # Try to open the file
                if ( sysopen $fd, $f, O_WRONLY | O_APPEND | O_CREAT ) {

                    # Done, now cache and return the filehandle
                    $fhandles{$f} = $fd;
                    $fpids{$f}    = $$;
                    $rv           = $fd;

                } else {

                    # Failed to do so, log the error
                    Paranoid::ERROR =
                        pdebug( "failed to open the file ($filename): $!",
                        PDLEVEL1 );
                    $rv = undef;
                }
            } else {
                Paranoid::ERROR =
                    pdebug( "failed to detaint filename: $filename",
                    PDLEVEL1 );
            }
        }

        return $rv;
    }

    sub init () {

        # Purpose:  Closes all opened filehandles by this process
        # Returns:  True (1)
        # Usage:    init();

        foreach ( keys %fhandles ) { _delHandle($_) }

        return 1;
    }
}

sub remove ($) {

    # Purpose:  Closes the requested file
    # Returns:  Return value of _delHandle();
    # Usage:    $rv = remove($filename);

    my $filename = shift;

    return _delHandle($filename);
}

sub log ($$$$$$$$) {

    # Purpose:  Logs the passed message to the named file
    # Returns:  Return value of print()
    # Usage:    log($msgtime, $severity, $message, $name, $facility, $level,
    #               $scope, $filename);

    my $msgtime  = shift;
    my $severity = shift;
    my $message  = shift;
    my $name     = shift;
    my $facility = shift;
    my $level    = shift;
    my $scope    = shift;
    my $filename = shift;
    my $rv       = 0;
    my $fh;

    # Validate arguments
    croak 'Mandatory third argument must be a valid message'
        unless defined $message;
    croak 'Mandatory eighth argument must be a valid filename'
        unless defined $filename;

    pdebug(
        "entering w/($msgtime)($severity)($message)($name)"
            . "($facility)($level)($scope)($filename)",
        PDLEVEL1
        );
    pIn();

    # Message time defaults to current time
    $msgtime = time unless defined $msgtime;

    # Get the filehandle
    if ( defined( $fh = _getHandle($filename) ) ) {

        # Lock the filehandle
        flock $fh, LOCK_EX;

        # Move to the end of the file and print the message
        seek $fh, 0, SEEK_CUR;
        seek $fh, 0, SEEK_END;
        $rv = print $fh "$message\n";
        Paranoid::ERROR =
            pdebug( "failed to write to $filename: $!", PDLEVEL1 )
            unless $rv;

        # Unlock & close the file
        flock $fh, LOCK_UN;
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub dump ($) {

    # Purpose:  Exists purely for compliance.
    # Returns:  True (1)
    # Usage:    init();

    return ();
}

1;

__END__

=head1 NAME

Paranoid::Log::File - File Logging Functions

=head1 VERSION

$Id: File.pm,v 0.83 2010/04/15 23:23:28 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Log;
  
  enableFacility('events', 'file', 'debug', '+', $filename);

=head1 DESCRIPTION

This module logs messages to the log files, and is safe for use with forked
children logging to the same files.  Each child will open their own
filehandles and use advisory locking for writes.

This module should not be used directly, B<Paranoid::Log> should be your 
exclusive interface for logging.

=head1 SUBROUTINES/METHODS

B<NOTE>:  Given that this module is not intended to be used directly nothing
is exported.

=head2 init

=head2 log

=head2 remove

=head2 dump

=head1 DEPENDENCIES

=over

=item o

L<Fcntl>

=item o

L<Paranoid::Debug>

=item o

L<Paranoid::Filesystem>

=item o

L<Paranoid::Input>

=back

=head1 SEE ALSO

=over

=item o

L<Paranoid::Log>

=back

=head1 BUGS AND LIMITATIONS

This isn't a high performance module when dealing with a high logging rate
with high concurrency.  This is due to the advisory locking requirement and
the seeks to the end of the file with every message.  This facility is
intended as a kind of lowest-common demoninator for programs that need some
kind of logging capability.

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

