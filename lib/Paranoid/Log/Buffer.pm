# Paranoid::Log::Buffer -- Log buffer support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Buffer.pm,v 0.4 2008/02/27 06:53:00 acorliss Exp $
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

Paraniod::Log::Buffer - Log Buffer Functions

=head1 MODULE VERSION

$Id: Buffer.pm,v 0.4 2008/02/27 06:53:00 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Log::Buffer;

  $rv = init();
  $rv = remove($name);

  $rv = log($msgtime, $severity, $message, $name, $facility, $level, $scope,
            $bufferSize);

  @entries = dump($name);

=head1 REQUIREMENTS

Paranoid::Debug

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
argument to the call.  That number defines the size of the ring buffer in
terms of number of entries allowed.

B<NOTE:> Buffers are maintained within process memory.  If you fork
a process from a parent with a ring buffer each copy will maintain its own
entries.

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::Log::Buffer;

use strict;
use warnings;
use vars qw($VERSION);
use Paranoid::Debug;
use Carp;

($VERSION)    = (q$Revision: 0.4 $ =~ /(\d+(?:\.(\d+))+)/);

#####################################################################
#
# Module code follows
#
#####################################################################

=head1 FUNCTIONS

=cut

{

  # Buffers
  my %buffers = ();

  sub _getBuffer($) {
    # Returns the requested buffer, automatically creating them as needed.
    #
    # Usage:  $bref = _getBuffer($name);

    my $name  = shift;

    $buffers{$name} = [] unless exists $buffers{$name};

    return $buffers{$name};
  }

  sub _delBuffer($) {
    # Deletes the requested buffer.
    #
    # Usage: _delBuffer($name);

    my $name  = shift;

    delete $buffers{$name} if exists $buffers{$name};

    return 1;
  }

=head2 init

  $rv = init();

For the purposes of this module this function only deletes all ring buffers.

=cut

  sub init() {
    %buffers = ();

    return 1;
  }

}

=head2 remove

  $rv = remove($name);

This function removes the specified buffer from memory.  Remember,
however, that any subsequent attempts to log to that buffer will cause it to
automatically be recreated.

=cut

sub remove($) {
  my $name = shift;

  return _delBuffer($name);
}

=head2 log

  $rv = log($msgtime, $severity, $message, $name, $facility, $level, $scope,
            $bufferSize);

This function adds another log message to the named buffer.  This is
not meant to be used directly.  Please use the B<Paranoid::Log> module.
B<bufferSize> is optional.  It defaults to twenty entries unless otherwise
specified.

=cut

sub log($$$$$$$$) {
  my $msgtime   = shift;
  my $severity  = shift;
  my $message   = shift;
  my $name      = shift;
  my $facility  = shift;
  my $level     = shift;
  my $scope     = shift;
  my $buffSize  = shift;
  my $barg      = defined $buffSize ? $buffSize : 'undef';
  my $buffer    = _getBuffer($name);

  # Validate arguments
  croak "Invalid buffer name passed to Buffer::log()" unless defined $name;
  croak "Invalid message passed to Buffer::log()" unless defined $message;

  pdebug("entering w/($msgtime)($severity)($message)($name)($facility)" .
    "($level)($scope)($barg)", 9);
  pIn();

  # Buffer size defaults to twenty entries
  $buffSize = 20 unless defined $buffSize && $buffSize > 0;

  # Message time defaults to current time
  $msgtime = time() unless defined $msgtime;

  # Trim the buffer if needed
  splice(@$buffer, 0, $buffSize - 1) if scalar @$buffer > $buffSize;

  # Add the message
  push(@$buffer, [$msgtime, $message]);

  pOut();
  pdebug("leaving w/rv: 1", 9);

  return 1;
}

=head2 dump

  @entries = dump($name);

This dumps all current entries in the named buffer.  Each entry is an
array reference to a two-element array.  The first element is the timestamp
of the message (in UNIX epoch seconds), the second the actual message
itself.

=cut

sub dump($) {
  my $name    = shift;
  my $buffer  = _getBuffer($name);

  return @$buffer;
}

1;

=head1 SEE ALSO

Paranoid::Log(3)

=head1 HISTORY

None as of yet.

=head1 AUTHOR/COPYRIGHT

(c) 2005 Arthur Corliss (corliss@digitalmages.com)

=cut

