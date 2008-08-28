# Paranoid::Lockfile -- Paranoid Lockfile support
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Lockfile.pm,v 0.4 2008/08/28 06:22:51 acorliss Exp $
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

Paranoid::Lockfile - Paranoid Lockfile support

=head1 MODULE VERSION

$Id: Lockfile.pm,v 0.4 2008/08/28 06:22:51 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Lockfile;

  $rv = plock($lockfile);
  $rv = punlock($lockfile);
  $rv = pcloseLockfile($lockfile);

=head1 REQUIREMENTS

=over

=item o

Fcntl

=item o

Paranoid

=item o

Paranoid::Debug

=back

=head1 DESCRIPTION

This modules provides a relatively safe locking mechanism multiple processes.
This does not work over NFS or across remote systems, this is only intended
for use on a single system at a time, and only on those that support B<flock>.

B<sysopen> is used to avoid race conditions with multiple process attempting
to create the same file simultaneously.

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::Lockfile;

use strict;
use warnings;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use Exporter;
use Fcntl qw(:flock O_RDWR O_CREAT O_EXCL);
use Paranoid;
use Paranoid::Debug;
use Paranoid::Filesystem;
use Carp;

($VERSION)    = (q$Revision: 0.4 $ =~ /(\d+(?:\.(\d+))+)/);

@ISA          = qw(Exporter);
@EXPORT       = qw(plock punlock pcloseLockfile);
@EXPORT_OK    = qw(plock punlock pcloseLockfile);
%EXPORT_TAGS  = (
  all => [qw(plock punlock pcloseLockfile)],
  );

#####################################################################
#
# Module code follows
#
#####################################################################

=head1 FUNCTIONS

=cut 

{
  # file descriptor stash
  my %fd;

  sub _clearLocks {
    # Used primarily by the END block to cleanly
    # close all lock files;
    #
    # Usage:  _clearLocks();

    my ($frv, $rv);

    pdebug("entering", 10);
    pIn();

    $frv = 1;
    foreach (keys %fd) {
      $rv = pcloseLockfile($_);
      $frv = 0 unless $rv;
      pdebug("$_ rv: $rv", 11);
    }

    pOut();
    pdebug("leaving", 10);
  }

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

=cut

  sub plock ($;$$) {
    my $filename  = shift;
    my $type      = shift;
    my $mode      = shift;
    my $targ      = defined $type ? $type : 'undef';
    my $marg      = defined $mode ? $mode : 'undef';
    my $rv        = 0;
    my $fd;

    # Validate arguments
    croak "Mandatory first argument must be a defined filename" unless
      defined $filename && length($filename) > 0;
    croak "Optional second argument must be a valid lock type" unless
      ! defined $type || (defined $type && $type =~ /^(?:write|shared)$/);

    pdebug("entering w/($filename)($targ)($marg)", 9);
    pIn();

    # Get the filehandle if it's already open
    if (exists $fd{$filename}) {
      $fd = $fd{$filename};

    # Open a new filehandle
    } else {

      # Set the default perms if needed
      $mode = 0600 unless defined $mode;

      # To avoid race conditions with multiple files opening (and 
      # overwriting) the same file, and hence doing flocks on descriptors 
      # with a different # (f#*&ing lock isn't working!) we attempt to do 
      # an exclusive open first.  If that fails, then we do reopen to get 
      # a filehandle to the (possibly) newly created file.
      sysopen($fd, $filename, O_RDWR | O_CREAT | O_EXCL, $mode) ||
        sysopen($fd, $filename, O_RDWR);

      # Store the new filehandle
      $fd{$filename} = $fd if defined $fd;
    }

    # Flock it
    if (defined $fd) {

      # Assign the lock type according to $type
      $type = 'write' unless defined $type;
      $type = $type eq 'write' ? LOCK_EX : LOCK_SH;
      $rv = 1;
      flock $fd, $type;
    }

    pOut();
    pdebug("leaving w/rv: $rv", 9);

    return $rv;
  }

=head2 punlock

  $rv = punlock($filename);

This function removes any existing locks on the specified filename using
B<flock>.  If no previous lock existed or it was successful it returns true.
This does not, however, close the open filehandle to the lockfile.

=cut

  sub punlock ($) {
    my $filename  = shift;
    my $rv        = 1;

    # Validate arguments
    croak "Mandatory first argument must be a defined filename" unless 
      defined $filename && length($filename) > 0;

    pdebug("entering w/($filename)", 9);
    pIn();

    $rv = flock $fd{$filename}, LOCK_UN if exists $fd{$filename};

    pOut();
    pdebug("leaving w/rv: $rv", 9);

    return $rv;
  }

=head2 pcloseLockfile

  $rv = pcloseLockfile($filename);

This function releases any existing locks and closes the open filehandle to
the lockfile.  Returns true if the file isn't currently open or the operation
succeeds.

=cut

  sub pcloseLockfile ($) {
    my $filename  = shift;
    my $rv        = 1;

    # Validate arguments
    croak "Mandatory first argument must be a defined filename" unless 
      defined $filename && length($filename) > 0;

    pdebug("entering w/($filename)", 9);
    pIn();

    if (exists $fd{$filename}) {
      flock $fd{$filename}, LOCK_UN;
      $rv = close $fd{$filename};
      delete $fd{$filename} if $rv;
    }

    pOut();
    pdebug("leaving w/rv: $rv", 9);

    return $rv;
  }
}

END {
  _clearLocks();
}

1;

=head1 HISTORY

None.

=head1 AUTHOR/COPYRIGHT

(c) 2005 Arthur Corliss (corliss@digitalmages.com)

=cut

