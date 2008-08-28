# Paranoid::Module -- Paranoid Module Loading Routines
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Module.pm,v 0.3 2008/08/28 06:37:38 acorliss Exp $
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

Paranoid::Module -- Paranoid Module Loading Routines

=head1 MODULE VERSION

$Id: Module.pm,v 0.3 2008/08/28 06:37:38 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Module;

  $rv = loadModule($module, qw(:all));

=head1 REQUIREMENTS

=over

=item o

Paranoid

=item o

Paranoid::Debug

=back

=head1 DESCRIPTION

This provides a single function that allows you to do dynamic loading of
modules at runtime.

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::Module;

use strict;
use warnings;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use Exporter;
use Paranoid;
use Paranoid::Debug;
use Paranoid::Input;
use Carp;

($VERSION)    = (q$Revision: 0.3 $ =~ /(\d+(?:\.(\d+))+)/);

@ISA          = qw(Exporter);
@EXPORT       = qw(loadModule);
@EXPORT_OK    = qw(loadModule);
%EXPORT_TAGS  = (
  all => [qw(loadModule)],
  );

#####################################################################
#
# Module code follows
#
#####################################################################

=head1 FUNCTIONS

=cut

{

  my %tested;       # Hash of module names => boolean (load success)

=head2 loadModule

  $rv = loadModule($module, qw(:all));

Accepts a module name and an optional list of arguments to 
use with the import function.  Returns a true or false depending
whether the require was successful.  We do not currently
track the return value of the import function.

=cut

  sub loadModule ($;@) {
    my $module  = shift;
    my @args    = @_;
    my $rv      = 0;
    my $a       = @args ? join(' ', @args) : '';
    my $caller  = scalar caller;
    my $c       = defined $caller ? $caller : 'undef';
    my ($string, $m);

    croak "Mandatory first argument must be a defined module name" unless
      defined $module;

    pdebug("entering w/($module)($a)", 9);
    pIn();

    # Debug info
    pdebug("calling package: $c", 10);

    # Detaint module name
    if (detaint($module, 'filename', \$m)) {
      $module = $m;
    } else {
      Paranoid::ERROR = pdebug("failed to detaint module name", 9);
      $tested{$module} = 0;
    }

    # Skip if we've already done this
    unless (exists $tested{$module}) {

      # Try to load it
      $tested{$module} = eval "require $module; 1;" ? 1 : 0;

    }

    # Try to import symbol sets if requested
    if ($tested{$module} && defined $caller) {

      # Import requested symbol (sets)
      if (@args) {
        eval << "EOF";
{
  package $caller;
  import $module qw(@{[ join(' ', @args) ]});
  1;
}
EOF

      # Import default symbols if no args passed
      } else {
        eval << "EOF";
{
  package $caller;
  import $module;
  1;
}
EOF
      }
    }

    pOut();
    pdebug("leaving w/rv: $tested{$module}", 9);

    # Return result
    return $tested{$module};
  }
}

1;

=head1 HISTORY

None as of yet.

=head1 AUTHOR/COPYRIGHT

(c) 2005 Arthur Corliss (corliss@digitalmages.com)

=cut



