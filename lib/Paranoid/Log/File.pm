# Paranoid::Log::File -- File Log support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: File.pm,v 0.7 2008/08/28 06:39:40 acorliss Exp $
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

Paranoid::Log::File - File Logging Functions

=head1 MODULE VERSION

$Id: File.pm,v 0.7 2008/08/28 06:39:40 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Log::File;

  $rv = init();
  $rv = remove($filename);

  $rv = log($msgtime, $severity, $message, $name, $facility, $level, $scope,
            $filename);

=head1 REQUIREMENTS

=over

=item o

Fcntl

=item o

Paranoid::Debug

=item o

Paranoid::Filesystem

=back

=head1 DESCRIPTION

This module logs messages to the log files, and is safe for use with forked
children logging to the same files.  Each child will open their own
filehandles and use advisory locking for writes.

This module should not be used directly, B<Paranoid::Log> should be your 
exclusive interface for logging.

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::Log::File;

use strict;
use warnings;
use vars qw($VERSION);
use Paranoid::Debug;
use Paranoid::Filesystem;
use Paranoid::Input;
use Carp;
use Fcntl qw(:flock :seek O_WRONLY O_CREAT O_APPEND);

($VERSION)    = (q$Revision: 0.7 $ =~ /(\d+(?:\.(\d+))+)/);

#####################################################################
#
# Module code follows
#
#####################################################################

=head1 FUNCTIONS

=cut

{

  my %fhandles;
  my %fpids;

  sub _getHandle {
    # Returns a filehandle to the specified file.  It will automatically
    # create the file if necessary.  Also tracks which process opened up the
    # filehandle so a new one will be opened in a forked process.
    #
    # Usage:  $fh = _getHandle($filename);

    my $filename    = shift;
    my ($f, $fd, $rv);

    if (exists $fhandles{$filename}) {
      if ($fpids{$filename} == $$) {
        $rv = $fhandles{$filename};
      } else {
        delete $fhandles{$filename};
        $rv = _getHandle($filename);
      }
    } else {
      if (detaint($filename, 'filename', \$f)) {
        if (sysopen($fd, $f, O_WRONLY | O_APPEND | O_CREAT)) {
          $fhandles{$f} = $fd;
          $fpids{$f}    = $$;
          $rv = $fd;
        }
      } else {
        Paranoid::ERROR = pdebug("failed to detaint filename: $filename", 10);
      }
    }

    return $rv;
  }

  sub _delHandle {
    # Deletes any open filehandles for the specified filename.  Only closes
    # filehandles opened by this process.
    #
    # Usage:  $rv = _delHandle($filename);

    my $filename  = shift;
    my $rv        = 1;

    if (exists $fhandles{$filename} && $fpids{$filename} == $$) {
      $rv = close $fhandles{$filename};
      delete $fhandles{$filename};
      delete $fpids{$filename};
    }

    return $rv;
  }

=head2 init

  $rv = init();

For the purposes of this module this function closes any filehandles opened
by the current process.

=cut

  sub init() {
    foreach (keys %fhandles) { _delHandle($_) };

    return 1;
  }
}

=head2 remove

  $rv = remove($filename);

This function closes any open filehandles to the specified filename if they
were opened by the current process.

=cut

sub remove($) {
  my $filename  = shift;

  return _delHandle($filename);
}

=head2 log

  $rv = log($msgtime, $severity, $message, $name, $facility, $level, $scope,
            $filename);

This function adds another log message to the log file.  This is 
not meant to be used directly.  Please use the B<Paranoid::Log> module.

=cut

sub log($$$$$$$$) {
  my $msgtime   = shift;
  my $severity  = shift;
  my $message   = shift;
  my $name      = shift;
  my $facility  = shift;
  my $level     = shift;
  my $scope     = shift;
  my $filename  = shift;
  my $rv        = 0;
  my $fh;

  # Validate arguments
  croak "Mandatory third argument must be a valid message" unless defined
    $message;
  croak "Mandatory eighth argument must be a valid filename" unless defined
    $filename;

  pdebug("entering w/($msgtime)($severity)($message)($name)" .
    "($facility)($level)($scope)($filename)", 9);
  pIn();

  # Message time defaults to current time
  $msgtime = time() unless defined $msgtime;

  # Get the filehandle

  # Print to the open filehandle
  if (defined($fh = _getHandle($filename))) {

    # Lock the filehandle
    flock $fh, LOCK_EX;

    # Move to the end of the file
    seek $fh, SEEK_END, 0;
    $rv = print $fh "$message\n";
    Paranoid::ERROR = pdebug(
      "failed to write to $filename: $!", 9) unless $rv;

    # Unlock & close the file
    flock $fh, LOCK_UN;
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return 1;
}

sub dump($) {
  # This function is present only for compliance.

  return ();
}

1;

=head1 SEE ALSO

Paranoid::Log(3)

=head1 HISTORY

None as of yet.

=head1 AUTHOR/COPYRIGHT

(c) 2005 Arthur Corliss (corliss@digitalmages.com)

=cut

