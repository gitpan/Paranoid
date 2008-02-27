# Paranoid::Debug -- Debug support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Debug.pm,v 0.7 2008/01/23 06:48:04 acorliss Exp $
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

Paraniod::Debug - Trace message support for paranoid programs

=head1 MODULE VERSION

$Id: Debug.pm,v 0.7 2008/01/23 06:48:04 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Debug;

  PDEBUG = 1;
  PDPREFIX = sub { scalar localtime };
  pdebug("starting program", 1);
  foo();

  sub foo {
    pIn();
    pdebug("entering foo()", 2);
    pOut();
  }

  perror("error msg");

=head1 REQUIREMENTS

Paranoid

=head1 DESCRIPTION

The purpose of this module is to provide a barely useful framework to produce
debugging output.  With this module you can assign a level of detail to pdebug
statements, and they'll only be displayed when PDEBUG is set to that level or
higher.  This allows you to have your program produce varying levels of
debugging output.

Using the B<pIn> and B<pOut> functions at the beginning and end of each
function will cause debugging output to be indented appropriately so you can
visually see the level of recursion.

B<NOTE:> This module provides a function called B<perror> which conflicts with
a similar function provided by the B<POSIX> module.  If you use this module
you should avoid using or importing POSIX's version of this function.

B<NOTE:> All modules within the Paranoid framework use this module.  Their
debug levels range from 9 and up.  You should use 1 - 8 for your own modules
or code.

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::Debug;

use strict;
use warnings;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use Exporter;
use Paranoid;

($VERSION)    = (q$Revision: 0.7 $ =~ /(\d+(?:\.(\d+))+)/);

@ISA          = qw(Exporter);
@EXPORT       = qw(PDEBUG pdebug perror pIn pOut);
@EXPORT_OK    = qw(PDEBUG pdebug perror pIn pOut);
%EXPORT_TAGS  = (
  all => [qw(PDEBUG pdebug perror pIn pOut)],
  );

#####################################################################
#
# Module code follows
#
#####################################################################

=head1 VARIABLES

=head2 PDEBUG

B<PDEBUG> is initially 0, but can be set to any positive integer.  The higher
the number the higher the level of pdebug statements are printed.

=head2 PDPREFIX

B<PDPREFIX> is set, by default to a subroutine that produces the standard
prefix for debug messages:

  [PID - ILEVEL] Subroutine:

=cut

{
  my $ILEVEL = 0;   # Start with no identation
  my $PDEBUG = 0;   # Start with debug output disabled

  my $DEFPREFIX = sub {

    # Default Prefix to use with debug messages looks like:
    #
    #   [PID - ILEVEL] Subroutine:
    #
    my $caller = (caller(2))[3];
    my $prefix;

    $caller = defined $caller ? $caller : 'undef';
    $prefix = ' ' x $ILEVEL . "[$$-$ILEVEL] $caller: ";

    return $prefix;
    };
  my $PDPREFIX = $DEFPREFIX;

  sub PDEBUG   : lvalue { $PDEBUG };
  sub ILEVEL   : lvalue { $ILEVEL };
  sub PDPREFIX : lvalue { $PDPREFIX };
}

# TODO: Add a function to set the debug level from the specified argument on
# TODO: the command line.

# TODO: Add another flag to report the PID w/error messages

=head1 FUNCTIONS

=head2 perror

  perror("error msg");

This function prints the passed message to STDERR.

=cut

sub perror ($) {
  my $msg = shift;

  print STDERR "$msg\n";
}

=head2 pdebug

  pdebug("debug statement", 3);

This function is called with one mandatory argument (the string to be
printed), and an optional integer.  This integer is compared against B<PDEBUG>
and the debug statement is printed if PDEBUG is equal to it or higher.

The return value is always the debug statement itself.  This allows for a
single statement to produce debug output and set variables.  For instance:

  Paranoid::ERROR = pdebug("Something bad happened!", 3);

=cut

sub pdebug ($;$) {
  my $msg = shift;
  my $level = shift || 1;
  my $prefix = PDPREFIX;

  return $msg if $level > PDEBUG;

  # Execute the code block, if that's what it is
  $prefix = &$prefix() if ref($prefix) eq 'CODE';

  perror("$prefix$msg");

  return $msg;
}

=head2 pIn

  pIn();

This function causes all subsequent pdebug messages to be indented by one
additional space.

=cut

sub pIn () {
  my $i = ILEVEL;
  ILEVEL = ++$i;
}

=head2 pOut

  pOut();

This function causes all subsequent pdebug messages to be indented by one
less space.

=cut

sub pOut () {
  my $i = ILEVEL;
  ILEVEL = --$i;
}

1;

=head1 HISTORY

None as of yet.

=head1 AUTHOR/COPYRIGHT

(c) 2005 Arthur Corliss (corliss@digitalmages.com)

=cut

