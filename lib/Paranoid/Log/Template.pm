# Paranoid::Log::Template -- Log Facility Template for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Template.pm,v 0.4 2008/02/28 19:26:49 acorliss Exp $
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

Paraniod::Log::Template - Log Facility Template

=head1 MODULE VERSION

$Id: Template.pm,v 0.4 2008/02/28 19:26:49 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Log::Template;

  $rv = init();
  $rv = remove($name);

  $rv = log($msgtime, $severity, $message, $name, $facility, $level, $scope,
            @args);

  @entries = dump($name);

=head1 REQUIREMENTS

Paranoid::Debug

=head1 DESCRIPTION

This is a template for logging facilities which can be used by
B<Paranoid::Log>.  The functions above are the minimum required for proper
operation.  For specific examples please see the actual facilities bundled
with the the Paranoid modules.

These modules are typically not meant to be used directly, but through the
B<Paranoid::Log> interface only.

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::Log::Template;

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

=head2 init

  $rv = init();

This function is called the first time a logging facility is activated.  You
can use it to initialize an internal data structures necessary for proper
operation.

=cut

sub init() {
  return 1;
}

=head2 remove

  $rv = remove($name);

This function is called to deactivate a named instance of the logging
facility.

=cut

sub remove($) {
  my $name = shift;

  return 1;
}

=head2 log

  $rv = log($msgtime, $severity, $message, $name, $facility, $level, $scope,
            @args);

This function causes the passed message to be logged to whatever the named
instance represents.  This is a blocking call.

=cut

sub log($$$$$$$;@) {
  my $msgtime   = shift;
  my $severity  = shift;
  my $message   = shift;
  my $name      = shift;
  my $facility  = shift;
  my $level     = shift;
  my $scope     = shift;
  my @args      = @_;

  # Validate arguments
  croak "Invalid message passed to Template::log()" unless defined $message;

  pdebug("entering w/($msgtime)($severity)($message)($name)" .
    "($facility)($level)($scope)", 9);
  pIn();

  pOut();
  pdebug("leaving w/rv: 1", 9);

  return 1;
}

=head2 dump

  @entries = dump($name);

This is currently only useful for log buffers, in which case it dumps the
current contents of the buffer into an array and returns it.  All facilities
that do not support this should simply return an empty list.

=cut

sub dump($) {
  my $name    = shift;

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

