# Paranoid::Log::Buffer -- Log buffer support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Buffer.pm,v 0.8 2009/03/04 09:32:51 acorliss Exp $
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

package Paranoid::Log::Buffer;

use 5.006;

use strict;
use warnings;
use vars qw($VERSION);
use Paranoid::Debug qw(:all);
use Carp;

($VERSION) = ( q$Revision: 0.8 $ =~ /(\d+(?:\.(\d+))+)/sm );

#####################################################################
#
# Module code follows
#
#####################################################################

{

    # Buffers
    my %buffers = ();

    sub _getBuffer ($) {

        # Purpose:  Retrieves the named buffer (which is an array ref).
        #           Creates the array on the fly if it doesn't exist.
        # Returns:  Array ref
        #           False (0) if there are any errors
        # Usage:    $ref = _getBuffer($name);

        my $name = shift;

        $buffers{$name} = [] unless exists $buffers{$name};

        return $buffers{$name};
    }

    sub _delBuffer ($) {

        # Purpose:  Deletes the named buffer from the hash.
        # Returns:  True (1)
        # Usage:    _delBuffer($name);

        my $name = shift;

        delete $buffers{$name} if exists $buffers{$name};

        return 1;
    }

    sub init () {

        # Purpose:  Empties the named buffer hash
        # Returns:  True (1)
        # Usage:    init();

        %buffers = ();

        return 1;
    }

}

sub remove ($) {

    # Purpose:  Removes the requested buffer
    # Returns:  Return value of _delBuffer()
    # Usage:    $rv = remove($name);

    my $name = shift;

    return _delBuffer($name);
}

sub log ($$$$$$$$) {

    # Purpose:  Logs the passed message to the named buffer, trimming excess
    #           messages as needed
    # Returns:  True (1)
    # Usage:    log($msgtime, $severity, $message, $name, $facility, $level,
    #               $scope);
    # Usage:    log($msgtime, $severity, $message, $name, $facility, $level,
    #               $scope, $buffSize);

    my $msgtime  = shift;
    my $severity = shift;
    my $message  = shift;
    my $name     = shift;
    my $facility = shift;
    my $level    = shift;
    my $scope    = shift;
    my $buffSize = shift;
    my $barg     = defined $buffSize ? $buffSize : 'undef';
    my $buffer   = _getBuffer($name);

    # Validate arguments
    croak 'Mandatory third argument must be a valid message'
        unless defined $message;
    croak 'Mandatory fourth argument must be a defined buffer name'
        unless defined $name;

    pdebug(
        "entering w/($msgtime)($severity)($message)($name)($facility)"
            . "($level)($scope)($barg)",
        PDLEVEL1
    );
    pIn();

    # Buffer size defaults to twenty entries
    $buffSize = 20 unless defined $buffSize and $buffSize > 0;

    # Message time defaults to current time
    $msgtime = time unless defined $msgtime;

    # Trim the buffer if needed
    splice( @$buffer, 0, $buffSize - 1 ) if scalar @$buffer > $buffSize;

    # Add the message
    push @$buffer, [ $msgtime, $message ];

    pOut();
    pdebug( 'leaving w/rv: 1', PDLEVEL1 );

    return 1;
}

sub dump ($) {

    # Purpose:  Returns the contents of the named buffer
    # Returns:  Array
    # Usage:    @events = dump($name);

    my $name   = shift;
    my $buffer = _getBuffer($name);

    return @$buffer;
}

1;

__END__

=head1 NAME

Paranoid::Log::Buffer - Log Buffer Functions

=head1 VERSION

$Id: Buffer.pm,v 0.8 2009/03/04 09:32:51 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Log;
  
  enableFacility('events', 'buffer', 'debug', '+');
  enableFacility('more-events', 'buffer', 'debug', '+', 100);

  @messages = Paranoid::Log::Buffer::dump();

=head1 DESCRIPTION

This module implements named buffers to be used for logging purposes.
Each buffer is of a concrete size (definable by the developer) with a
max message length of 2KB.  Each message is stored with a timestamp.  Once
the buffer hits the maximun number of entries it begins deleting the oldest
messages as the new messages come in.

Buffers are created automatically on the fly, and messages trimmed
before being stored.

With the exception of the B<dump> function this module is not meant to be
used directly.  B<Paranoid::Log> should be your exclusive interface for
logging.

When enabling a buffer facility with B<Paranoid::Log> you can add one integral
argument to the call.  That number defines the size of the log buffer in
terms of number of entries allowed.

B<NOTE:> Buffers are maintained within process memory.  If you fork
a process from a parent with a log buffer each copy will maintain its own
entries.

=head1 SUBROUTINES/METHODS

B<NOTE>:  Given that this module is not intended to be used directly nothing
is exported.

=head2 Paranoid::Log::Buffer::dump

  @entries = Paranoid::Log::Buffer::dump($name);

This dumps all current entries in the named buffer.  Each entry is an
array reference to a two-element array.  The first element is the timestamp
of the message (in UNIX epoch seconds), the second the actual message
itself.

=head1 DEPENDENCIES

=over

=item o

Paranoid::Debug

=back

=head1 SEE ALSO

=over

=item o

L<Paranoid::Log>

=back

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

