# Paranoid::Process -- Process management support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Process.pm,v 0.8 2008/08/28 06:22:51 acorliss Exp $
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

Paranoid::Process - Process Management Functions

=head1 MODULE VERSION

$Id: Process.pm,v 0.8 2008/08/28 06:22:51 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Process;

  MAXCHILDREN = 100;

  $SIG{CHLD} = \&sigchld;
  $count = childrenCount();
  installChldHandler($sub);
  $rv = pfork();

  $uid = ptranslateUser("foo");
  $gid = ptranslateGroup("foo");
  $rv = switchUser($user, $group);

  $rv = pcapture($cmd, \$crv, \$out);

=head1 REQUIREMENTS

=over

=item o

Paranoid

=item o

Paranoid::Debug

=item o

POSIX

=back

=head1 DESCRIPTION

This module provides a few functions meant to make life easier when managing
processes.  The following export targets are provided:

  all               All functions within this module
  pfork             All child management functions

Only the function B<switchUser> is currently exported by default.

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::Process;

use strict;
use warnings;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use Exporter;
use Paranoid;
use Paranoid::Debug;
use POSIX qw(getuid setuid setgid WNOHANG);
use Carp;

($VERSION)    = (q$Revision: 0.8 $ =~ /(\d+(?:\.(\d+))+)/);

@ISA          = qw(Exporter);
@EXPORT       = qw(switchUser);
@EXPORT_OK    = qw(MAXCHILDREN      childrenCount   installChldHandler
                   sigchld          pfork           ptranslateUser
                   ptranslateGroup  switchUser      pcapture);
%EXPORT_TAGS  = (
  all   => [qw(MAXCHILDREN      childrenCount   installChldHandler 
               sigchld          pfork           ptranslateUser
               ptranslateGroup  switchUser      pcapture)],
  pfork => [qw(MAXCHILDREN      childrenCount   installChldHandler
               sigchld          pfork)],
  );

#####################################################################
#
# Module code follows
#
#####################################################################

=head1 VARIABLES

=head2 MAXCHILDREN

Setting this variable sets a limit to how many children will be forked at a
time by B<pfork>.  The default is zero, which allows unlimited children.  Once
the limit is met pfork becomes a blocking call until a child exits so the new
one can be spawned.

=head1 FUNCTIONS

=head2 childrenCount

  $count = childrenCount();

This function returns the current number of children spawned by B<pfork>.

=head2 installChldHandler

  installChldHandler($sub);

This function takes a reference to a subroutine.  If used the subroutine will
be called every time a child exits.  That subroutine will be called with the
child's PID and exit value as arguments.

=cut

{
  my $maxChildren = 0;
  my $numChildren = 0;
  my $chldRef     = undef;

  sub MAXCHILDREN : lvalue {
    $maxChildren;
  }
  sub childrenCount () { return $numChildren };
  sub _incrChildren () { $numChildren++ };
  sub _decrChildren () { $numChildren-- };
  sub installChldHandler ($) {
    $chldRef = shift;

    croak "installChldHandler passed no sub ref!" unless
      defined $chldRef && ref($chldRef) eq 'CODE';
  }
  sub _chldHandler () { return $chldRef };
}

=head2 sigchld

  $SIG{CHLD} = \&sigchld;

This function decrements the child counter necessary for pfork's operation, as
well as calling the user's signal handler with each child's PID and exit
value.

=cut

sub sigchld () {
  my ($osref, $pid);
  my $sref = _chldHandler();

  # Remove the signal handler so we're not preempted
  $osref = $SIG{CHLD};
  $SIG{CHLD} = sub { 1 };

  # Process children exit values
  do {
    $pid = waitpid -1, WNOHANG;
    if ($pid > 0) {
      _decrChildren();
      pdebug("child $pid reaped w/rv: $?", 9);

      # Call the user's sig handler if defined
      &$sref($pid, $?) if defined $sref;
    }
  } until $pid < 1;

  # Reinstall the signal handler
  $SIG{CHLD} = $osref;
}

=head2 pfork

  $rv = pfork();

This function should be used in lieu of Perl's fork if you want to take
advantage of a blocking fork call that respects the MAXCHILDREN limit.  Use of
this function, however, also assumes the use of B<sigchld> as the signal
handler for SIGCHLD.

=cut

sub pfork () {
  my $max   = MAXCHILDREN();
  my ($rv, $rvarg);

  pdebug("entering", 9);
  pIn();

  # Check children limits and wait, if necessary
  if ($max) {
    while ($max <= childrenCount()) { sleep 1 };
  }

  # Fork and return
  $rv = fork;
  _incrChildren() if defined $rv;
  $rvarg = defined $rv ? $rv : 'undef';

  pOut();
  pdebug("leaving w/rv: $rvarg", 9);

  return $rv;
}

=head2 ptranslateUser

  $uid = ptranslateUser("foo");

This function takes a username and returns the corresponding UID as returned
by B<getpwent>.  If no match is found it returns undef.

=cut

sub ptranslateUser ($) {
  my $user = shift;
  my ($uuid, @pwentry, $rv, $rvarg);

  # Validate arguments
  croak "Mandatory first argument must be a defined username" unless
    defined $user;

  pdebug("entering w/($user)", 9);
  pIn();

  setpwent();
  do {
      @pwentry = getpwent();
      $uuid = $pwentry[2] if @pwentry && $user eq $pwentry[0];
      } until defined $uuid || ! scalar @pwentry;
  endpwent();
  $rv = $uuid if defined $uuid;
  $rvarg = defined $rv ? $rv : 'undef';

  pOut();
  pdebug("leaving w/rv: $rvarg", 9);

  return $rv;
}

=head2 ptranslateGroup

  $gid = ptranslateGroup("foo");

This function takes a group name and returns the corresponding GID as returned
by B<getgrent>.  If no match is found it returns undef.

=cut

sub ptranslateGroup ($) {
  my $group = shift;
  my ($ugid, @pwentry, $rv, $rvarg);

  # Validate arguments
  croak "Mandatory first argument must be a defined group name" unless
    defined $group;

  pdebug("entering w/($group)", 9);
  pIn();

  setgrent();
  do {
      @pwentry = getgrent();
      $ugid = $pwentry[2] if @pwentry && $group eq $pwentry[0];
      } until defined $ugid || ! scalar @pwentry;
  endgrent();
  $rv = $ugid if defined $ugid;
  $rvarg = defined $rv ? $rv : 'undef';

  pOut();
  pdebug("leaving w/rv: $rvarg", 9);

  return $rv;
}

=head2 ptranslateGroup

=head2 switchUser

  $rv = switchUser($user, $group);

This function can be fed one or two arguments, both either named user or
group, or UID or GID.  The group argument is optional, but you can pass undef
as the user to only switch the group.

=cut

sub switchUser ($;$) {
  my $user    = shift;
  my $group   = shift;
  my $uarg    = defined $user ? $user : 'undef';
  my $garg    = defined $group ? $group : 'undef';
  my $rv      = 1;
  my (@pwentry, $duid, $dgid);

  # Validate arguments
  croak "Mandatory argument of either user or group must be passed" unless
    defined $user || defined $group;

  pdebug("entering w/($uarg)($garg)", 9);
  pIn();

  # First switch the group
  if (defined $group) {

    # Look up named group
    unless ($group =~ /^\d+$/) {
      $dgid = ptranslateGroup($group);
      unless (defined $dgid) {
        Paranoid::ERROR = pdebug("couldn't identify group " .
          "($group)", 9);
        $rv = 0;
      }
    }

    # Switch to group
    if ($rv) {
      pdebug("switching to GID $dgid", 10);
       unless (setgid($dgid)) {
        Paranoid::ERROR = pdebug("couldn't switch to group " .
          "($group): $!", 9);
        $rv = 0;
      }
    }
  }

  # Second, switch the user
  if ($rv && defined $user) {

    # Look up named user
    unless ($user =~ /^\d+$/) {
      $duid = ptranslateUser($user);
      unless (defined $duid) {
        Paranoid::ERROR = pdebug("couldn't identify user " .
          "($user)", 9);
        $rv = 0;
      }
    }

    # Switch to user
    if ($rv) {
      pdebug("switching to UID $duid", 10);
      unless (setuid($duid)) {
        Paranoid::ERROR = pdebug("couldn't switch to user " .
          "($user): $!", 9);
        $rv = 0;
      }
    }
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 pcapture

  $rv = pcapture($cmd, \$crv, \$out);

This function executes the passed shell command and returns one of the following
three values:

  RV    Description
  =======================================================
  -1    Command failed to execute or died with signal
   0    Command executed but exited with a non-0 RV
   1    Command executed and exited with a 0 RV

The actual return value is populated in the passed scalar reference, while all
STDERR/STDOUT output is stored in the last scalar reference.  Any errors
executing the command will have the error string stored in B<Paranoid::ERROR>.

If the command exited cleanly it will automatically be bit shifted eight
bits.

B<NOTE:> Unlike many other functions in this suite it is up to you to detaint
the command passed to this function yourself.  There's simply no way for me to
know ahead of time what kind of convoluted arguments you might be handing this
call before system is called.  Failing to detaint that argument will cause
your script to exit under taint mode.

=cut

sub pcapture ($$$) {
  my $cmd   = shift;
  my $cref  = shift;
  my $oref  = shift;
  my $rv    = -1;

  # Validate arguments
  croak "Mandatory first argument must be a defined shell command string"
    unless defined $cmd;
  croak "Mandatory second argument must be a scalar reference" unless
    defined $cref && ref($cref) eq 'SCALAR';
  croak "Mandatory third argument must be a scalar reference" unless
    defined $oref && ref($oref) eq 'SCALAR';

  pdebug("entering w/($cmd)($cref)($oref)", 9);
  pIn();

  # Massage the command string
  $cmd = "( $cmd ) 2>&1";

  # Execute and snarf the output
  pdebug("executing command", 9);
  $$oref = `$cmd`;
  $$cref = $?;

  # Check the return value
  #
  # Okay, this first one is a big stretch, but since we're executing a command
  # in a subshell we won't get -1 like normal, but that shell should return
  # with a most probably non-portable return code of 32512...
  #
  # Son of a gun, it's portable as far as Solaris & Linux...
  if ($$cref == 32512) {
    Paranoid::ERROR = pdebug("command failed to execute: $!", 9);

  # The above note means that I'm probably screwed for this test case in so
  # many ways...
  } elsif ($$cref & 127) {
    Paranoid::ERROR = pdebug("command died with signal: @{[ $$cref & 127 ]}",
      9);

  # Let's pretend there are no problems, though, and here we are!
  } else {
    $$cref >>= 8;
    pdebug("command exited with rv: $$cref", 9);
    $rv = $$cref == 0 ? 1 : 0;
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

1;

=head1 EXAMPLES

=head2 pfork

This following example caps the number of children processes to three at a
time:

  $SIG{CHLD}  = \&sigchld;
  MAXCHILDREN = 3;
  for (1 .. 5) {

    # Only the children execute the following block
    unless ($pid = pfork()) {
      # ....
      exit 0;
    }
  }

You can also install a child-exit routine to be called by sigchld.
For instance, to track the children's history in the parent:

  sub recordChild ($$) {
    my ($cpid, $cexit) = @_;

    push(@chistory, [$cpid, $cexit]);
  }

  installChldHandler(\&recordChild);
  for (1 .. 5) {
    unless ($pid = pfork()) {
      # ....
      exit $rv;
    }
  }

  # Prints the child process history
  foreach (@chistory) { print "PID: $$_[0] EXIT: $$_[1]\n" };

=head1 HISTORY

None as of yet.

=head1 AUTHOR/COPYRIGHT

(c) 2005 Arthur Corliss (corliss@digitalmages.com)

=cut

