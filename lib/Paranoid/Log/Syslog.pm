# Paranoid::Log::Syslog -- Log Facility Syslog for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Syslog.pm,v 0.4 2008/02/28 19:26:49 acorliss Exp $
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

Paraniod::Log::Syslog - Log Facility Syslog

=head1 MODULE VERSION

$Id: Syslog.pm,v 0.4 2008/02/28 19:26:49 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Log::Syslog;

  $rv = init();
  $rv = remove($name);

  $rv = log($msgtime, $severity, $message, $name, $facility, $level, $scope);

=head1 REQUIREMENTS

Paranoid::Debug

Unix::Syslog

=head1 DESCRIPTION

This modules provides syslog facilities for B<Paranoid::Log>.

These modules are typically not meant to be used directly, but through the
B<Paranoid::Log> interface only.

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::Log::Syslog;

use strict;
use warnings;
use vars qw($VERSION);
use Paranoid::Debug;
use Unix::Syslog qw(:macros :subs);
use Carp;

($VERSION)    = (q$Revision: 0.4 $ =~ /(\d+(?:\.(\d+))+)/);

#####################################################################
#
# Module code follows
#
#####################################################################

=head1 FUNCTIONS

=cut

sub _setIdent (;$) {
  my $name  = shift;

  # Use $0 by default
  $name = $0 unless defined $name;

  # Strip path
  $name =~ s#^.*/##;

  return $name
}

=head2 init

  $rv = init();

=cut

sub init (;@) {
  return 1;
}

sub _transFacility ($) {
  # This function translates the non-prefixed log facility into the integral
  # constants.  It will return undef if the facility is invalid.
  #
  # Usage:  $f = _transFacility('user');

  my $f     = lc(shift);
  my %trans = (
    authpriv    => LOG_AUTHPRIV,        auth        => LOG_AUTHPRIV,
    cron        => LOG_CRON,            daemon      => LOG_DAEMON,
    ftp         => LOG_FTP,             kern        => LOG_KERN,
    local0      => LOG_LOCAL0,          local1      => LOG_LOCAL1,
    local2      => LOG_LOCAL2,          local3      => LOG_LOCAL3,
    local4      => LOG_LOCAL4,          local5      => LOG_LOCAL5,
    local6      => LOG_LOCAL6,          local7      => LOG_LOCAL7,
    lpr         => LOG_LPR,             mail        => LOG_MAIL,
    news        => LOG_NEWS,            syslog      => LOG_SYSLOG,
    user        => LOG_USER,            uucp        => LOG_UUCP,
    );

  return exists $trans{$f} ? $trans{$f} : undef;
}

sub _transLevel ($) {
  # This function translates the non-prefixed log level into the integral
  # constants.  It will return undef if the level is invalid.
  #
  # Usage:  $l = _transLevel('notice');

  my $l     = lc(shift);
  my %trans = (
    debug         => LOG_DEBUG,       info          => LOG_INFO,
    notice        => LOG_NOTICE,      warn          => LOG_WARNING,
    warning       => LOG_WARNING,     err           => LOG_ERR,
    crit          => LOG_CRIT,        alert         => LOG_ALERT,
    emerg         => LOG_EMERG,       error         => LOG_ERR,
    );

  return exists $trans{$l} ? $trans{$l} : undef;
}

{
  my $sysopened = 0;

  sub _openSyslog (;$$) {
    # This function exits true if the syslogger is already open, otherwise
    # trys to open it. Both arguments are optional.
    #
    # Usage:  _opensyslog($ident, $facility);

    my $ident     = shift;
    my $facility  = shift;
    my $i         = defined $ident    ? $ident    : 'undef';
    my $f         = defined $facility ? $facility : 'undef';

    pdebug("entering w/($i)($f)", 10);
    pIn();

    # Open a handle to the syslog daemon
    unless ($sysopened) {

      # Make sure both values are set
      $ident    = _setIdent($ident);
      $facility = 'user' unless defined $facility;

      # Validate the facility
      croak "Can't open handle to syslogger with an invalid facility: " .
        "$facility\n" unless defined($facility = _transFacility($facility));

      # Open the logger
      openlog $ident, LOG_CONS | LOG_NDELAY | LOG_PID, $facility;
      $sysopened = 1;
    }

    pOut();
    pdebug("leaving w/rv: $sysopened", 10);

    return $sysopened;
  }

=head2 remove

  $rv = remove();

This closes the logger.  This may be pointless, however, since it is
(re)opened automatically with every call to B<log>.

=cut

  sub remove (;$) {

    pdebug("entering", 10);

    closelog();
    $sysopened = 0;

    pdebug("leaving w/rv: 1");

    return 1;
  }

}

=head2 log

  $rv = log($msgtime, $severity, $message, $name, $facility, $level, $scope);

This function causes the passed message to be logged to the syslogger.  Only
$message is mandatory.  Facility and severity will default to B<user.notice>
if not specified.

B<NOTE:> The syslog facility is set in this case by the B<$name> argument, not
the B<$facility>.  The latter argument refers to a logging facility in
B<Paranoid's> context.

B<NOTE:> The syslog facility cannot be changed per-call to B<log>.  The only
way to change that is to call B<remove> before calling B<log>.

=cut

sub log($$$$$$$) {
  my $msgtime   = shift;
  my $severity  = shift;
  my $message   = shift;
  my $name      = shift;
  my $facility  = shift;
  my $level     = shift;
  my $scope     = shift;
  my $narg      = defined $name     ? $name     : 'undef';
  my $sarg      = defined $severity ? $severity : 'undef';
  my $rv        = 0;

  # Set defaults on optional args
  $name     = 'user'   unless defined $name;
  $severity = 'notice' unless defined $severity;

  # Validate arguments
  croak "Invalid message passed to Syslog::log" unless defined $message;
  croak "Invalid facility passed to Syslog::log: $narg" unless
    defined _transFacility($name);
  croak "Invalid severity passed to Syslog::log: $sarg" unless
    defined _transLevel($severity);

  pdebug("entering w/($message)($narg)($sarg)", 9);
  pIn();

  # Make sure the logger is ready and log the message
  if (_openSyslog(undef, $name)) {
    syslog _transLevel($severity), '%s', $message;
    $rv = 1;
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

sub dump() {
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

