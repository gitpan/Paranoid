# Paranoid -- Paranoia support for safer programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Paranoid.pm,v 0.16 2008/02/27 17:56:12 acorliss Exp $
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

Paranoid - Paranoia support for safer programs

=head1 MODULE VERSION

$Id: Paranoid.pm,v 0.16 2008/02/27 17:56:12 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid;

  $errMsg = Paranoid::ERROR;

  psecureEnv("/bin:/usr/bin");

=head1 REQUIREMENTS

None.

=head1 DESCRIPTION

This collection of modules started out as modules which perform things
(debatably) in a safer and taint-safe manner.  Since then it's also grown to
include functionality that fit into the same framework and conventions of the
original modules, including keeping the debug hooks for command-line
debugging.

All the modules below are intended to be used directly in your programs if you
need the functionality they provide.

This module does provide one function meant to secure your environment 
enough to satisfy taint-enabled programs, and as a container which holds the 
last reported error from any code in the Paranoid framework.

B<NOTE:>  at one point this module enforced use of B<taint> mode in all
scripts using it.  I no longer do that because I want to use this in other
modules that never required that constraint, and I don't want to piss off too
many users right off the bat.  That being said:  B<ALWAYS USE TAINT MODE IF
YOU CAN>.

=head1 CHILD MODULES

The following modules are available for use.  You should check their POD for
specifics on use:

  Paranoid::BerkeleyDB
  Paranoid::Debug
  Paranoid::Filesystems
  Paranoid::Input
  Paranoid::Lockfile
  Paranoid::Log
  Paranoid::Module
  Paranoid::Network
  Paranoid::Process

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid;

use strict;
use warnings;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use Exporter;

($VERSION)    = (q$Revision: 0.16 $ =~ /(\d+(?:\.(\d+))+)/);

@ISA          = qw(Exporter);
@EXPORT       = qw(psecureEnv);
@EXPORT_OK    = qw(psecureEnv);
%EXPORT_TAGS  = (
                  all   => [ qw(psecureEnv) ],
                 );

#####################################################################
#
# Module code follows
#
#####################################################################

#BEGIN {
  #die "This module requires taint mode to be enabled!\n" unless
  #  ${^TAINT} == 1;
  #delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
  #$ENV{PATH} = '/bin:/sbin:/usr/bin:/usr/sbin';
  #no ops qw(backtick system exec);
  #  :subprocess = system, backtick, exec, fork, glob
  #  :dangerous = syscall, dump, chroot
  #  :others = mostly IPC stuff
  #  :filesys_write = link, unlink, rename, mkdir, rmdir, chmod, 
  #                   chown, fcntl
  #  :sys_db = getpwnet, etc.
#}

=head1 FUNCTIONS

=head2 psecureEnv

  psecureEnv("/bin:/usr/bin");

This function deletes some of the dangerous environment variables that can be
used to subvert perl when being run in setuid applications.  It also sets the
path, either to the passed argument (if passed) or a default of
"/bin:/usr/bin".

=cut

sub psecureEnv(;$) {
  my $path = shift @_;

  $path = "/bin:/usr/bin" unless defined $path;

  delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
  $ENV{PATH} = $path;
}

=head2 Paranoid::ERROR

This lvalue function is not exported and must be referenced via the 
B<Paranoid> namespace.

=cut

{
  my $ERROR = '';

  sub ERROR : lvalue {
    $ERROR;
  }
}

1;

=head1 HISTORY

None as of yet.

=head1 AUTHOR/COPYRIGHT

(c) 2005 Arthur Corliss (corliss@digitalmages.com)

=cut

