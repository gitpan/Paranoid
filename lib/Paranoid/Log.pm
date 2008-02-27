# Paranoid::Log -- Log support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Log.pm,v 0.9 2008/02/27 06:49:23 acorliss Exp $
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

Paraniod::Log - Log Functions

=head1 MODULE VERSION

$Id: Log.pm,v 0.9 2008/02/27 06:49:23 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Log;

  clearLogDist();
  initLogDist();

  $rv = enableFacility($name, $facility, $logLevel, $scope, @args);
  $rv = disableFacility($name);

  $rv = plog($severity, $message);
  $rv = psyslog($severity, $message);

  # The following functions are not exported by default
  clearLogDist();
  initLogDist();
  $timeStamp = ptimestamp();

=head1 REQUIREMENTS

Paranoid::Debug

Paranoid::Module

=head1 DESCRIPTION

This module provides a unified interface and distribution for multiple
logging mediums.  By calling one function (B<plog>) you can have that
message stored in multiple mediums depending on what you've enabled at what
severities.  For instance, you could have a critical message not only
automatically logged in a log file and syslog, but it could also generate an
e-mail.

You can also use your own logging facility modules as long as you adhere to
the expected API (detailed below).  Just pass the name of the module as the
facility in B<enableFacility>.

=head1 LOGGING FACILITIES

Each logging facility is implemented as separate module consisting of
non-exported functions with conform to a a consistent API.  Each
facility module must have the following functions:

  Function        Description
  ------------------------------------------------------
  init            Called when module first loaded
  remove          Removes a named instance of the facility
  log             Logs the passed message
  dump            Dumps internal information

The B<init> function is only called once -- the first time the module is
used and accessed.

The B<remove> function allows you to remove a specific named instance of the
logging facility from use.

The B<log> function is used to actually log an entry into the facility.

The B<dump> function is used to dump pertinent internal data on the
requested named instance.  This is primarily intended for use with
facilities like the log buffer, in which case it dumps the contents of the
named buffer.  Other uses for this is left to the developer of individual
facility modules.

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::Log;

use strict;
use warnings;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use Exporter;
use Paranoid::Debug;
use Paranoid::Module;
use Carp;

($VERSION)    = (q$Revision: 0.9 $ =~ /(\d+(?:\.(\d+))+)/);

@ISA          = qw(Exporter);
@EXPORT       = qw(enableFacility disableFacility plog psyslog);
@EXPORT_OK    = qw(enableFacility disableFacility clearLogDist 
                   initLogDist plog ptimestamp psyslog);
%EXPORT_TAGS  = (
  all   => [qw(enableFacility disableFacility clearLogDist initLogDist 
               plog ptimestamp psyslog)],
  );

my @LEVELS  = qw(debug info notice warn warning err error crit alert 
                 emerg panic);

# Taken from syslog.h
#use constant LOG_EMERG      => 0;       # system is unusable
#use constant LOG_ALERT      => 1;       # action must be taken immediately
#use constant LOG_CRIT       => 2;       # critical conditions
#use constant LOG_ERR        => 3;       # error conditions
#use constant LOG_WARNING    => 4;       # warning conditions
#use constant LOG_NOTICE     => 5;       # normal but significant condition
#use constant LOG_INFO       => 6;       # informational
#use constant LOG_DEBUG      => 7;       # debug-level messages

#####################################################################
#
# Module code follows
#
#####################################################################

=head1 FUNCTIONS

=cut

{

  sub _convertLevel ($) {
    # Converts level synonyms to their primary names
    my $level   = shift;

    return $level eq 'panic'   ? 'emerg' :
           $level eq 'error'   ? 'err'   :
           $level eq 'warning' ? 'warn'  :
           $level;
  }

  # Stores whether them modules was loaded
  my %loaded = ();

  # Stores a reference to the module's log function
  my %logRefs = ();

  sub _loadModule ($) {
    # Loads the requested module if it hasn't been already.  Attempts first
    # to load the module relative to Paranoid::Log, or if that fails, as
    # a stand-alone module.
    #
    # Usage:  $rv = _loadModule($module);

    my $module    = ucfirst(shift);
    my $sref;
    my $rv;

    pdebug("entering w/($module)", 10);
    pIn();

    # First attempt to load module under Paranoid::Log

    # Return the status of the requested module if it was already
    # autoloaded.
    if (exists $loaded{$module}) {
      $rv = $loaded{$module};

    # Otherwise, try to load it now
    } else {

      # First attempt under the Paranoid::Log::* namespace
      $rv = $module eq 'Stderr' ? 1 : 
        loadModule("Paranoid::Log::$module", '') &&
        eval "Paranoid::Log::${module}::init();" &&
        eval "\$sref = \\&Paranoid::Log::${module}::log;" ? 1 :
        0;

      # Second attempt in its own namespace
      unless ($rv) {
        $rv = (loadModule($module, '') && eval "${module}::init();" &&
          eval "\$sref = \\&${module}::log;") ? 1 : 0;
      }

      # Cache & report the results
      if ($rv) {
        $loaded{$module} = 1;
        $logRefs{$module} = $sref;
        pdebug("successfully loaded $module",
          10);
      } else {
        $loaded{$module} = 0;
        pdebug("failed to load $module", 10);
      }
    }

    pOut();
    pdebug("leaving w/rv: $rv", 10);

    return $rv;
  }

  sub _getLogRef ($) {
    # Returns the requested log function reference.
    #
    # Usage:  $ref = _getLogRef($module);

    my $module      = ucfirst(shift);

    return exists $logRefs{$module} ? $logRefs{$module} : undef;
  }

  # This has consists of the name/array key/value pairs.  Each associated
  # array consists of the following entries: 
  #        [ $name, $facility, $level, $scope, @optionalArgs].
  my %loggers = ();

  sub _addLog ($$$$;@) {
    # Adds a named logger to the hash.  Returns true if successful, false if
    # not, should that named entry already exist.
    #
    # Usage:  $rv = _addLog($name, $level, $scope);

    my $name      = shift;
    my $facility  = shift;
    my $level     = shift;
    my $scope     = shift;
    my @args      = @_;
    my $rv;

    # Convert level synonyms
    $level = _convertLevel($level);

    # Make sure the module can be loaded
    unless (_loadModule(ucfirst($facility))) {
      Paranoid::ERROR = perror(
        "Couldn't load requested logging facility ($facility)!");
      return 0;
    }

    # Make sure the entry does not exist
    if (exists $loggers{$name}) {
      return 0;
    } else {
      $loggers{$name} = [$name, $facility, $level, $scope, @args];
      return 1;
    }
  }

  sub _delLog ($) {
    # Removes the named logger from the hash.  Always returns true.
    #
    # Usage:  _delLog($name);

    my $name = shift;

    delete $loggers{$name} if exists $loggers{$name};

    return 1;
  }

  # This hash gets populated in log level/logger names key/value pairs.
  # I.e., emerg => [ logger1, logger2, ...n ]
  my %distribution = ();

  sub _getDistRef () {
    # Returns a reference to the %distribution hash
    #
    # Usage:  $href = _getDistribution();

    return \%distribution;
  }

=head2 clearLogDist

  clearLogDist();

This empties all enabled loggers from the distribution processor.  It
doesn't erase any named logging facilities already put into place, simply
takes out of the distribution system so no further log entries will be
processed.

This can be used to temporarily halt all logging.

=cut

  sub clearLogDist () {
    pdebug("entering", 9);

    %distribution = (
      'emerg'       => [],
      'alert'       => [],
      'crit'        => [],
      'err'         => [],
      'warn'        => [],
      'notice'      => [],
      'info'        => [],
      'debug'       => [],
      );

    pdebug("leaving", 9);
  }

=head2 initLogDist

  initLogDist();

This goes through the list of named loggers and sets up the distribution
processor to feed them the applicable log entries as they come in.

This can be used to re-enable logging.

=cut

  sub initLogDist () {
    my @logNames = keys %loggers;
    my %lndx     = (
      'debug'       => 0,
      'info'        => 1,
      'notice'      => 2,
      'warn'        => 3,
      'err'         => 4,
      'crit'        => 5,
      'alert'       => 6,
      'emerg'       => 7,
      );
    my ($l, $s, $n);

    pdebug("entering", 9);
    pIn();

    # Make sure %distribution is cleared
    clearLogDist();

    # Populate each log level applicable to each named logger
    foreach (@logNames) {
      ($l, $s) = @{ $loggers{$_} }[2,3];
      $n       = $lndx{$l};

      pdebug("processing $_ ($s$l)", 10);

      # Set only the specified level
      if ($s eq '=') {
        pdebug("adding $_ to $l", 11);
        push(@{ $distribution{$l} }, $loggers{$_});

      # Set everything this level or lower priority
      } elsif ($s eq '-') {
        while ($n >= 0) {
          pdebug("adding $_ to $LEVELS[$n]", 11);
          push(@{ $distribution{$LEVELS[$n]} }, $loggers{$_});
          $n--;
        }

      # Set everything this level or higher
      } elsif ($s eq '+') {
        while ($n <= 7) {
          pdebug("adding $_ to $LEVELS[$n]", 11);
          push(@{ $distribution{$LEVELS[$n]} }, $loggers{$_});
          $n++;
        }
      }
    }

    pOut();
    pdebug("leaving", 9);
  }

  my $hostname;

  sub _getHostname () {
    my $fd;

    # Return cached result
    return $hostname if defined $hostname;

    # Get the current hostname
    if (-x '/bin/hostname') {
      if (open($fd, '/bin/hostname |')) {
        chomp($hostname = <$fd>);
        close($fd);
      }
    }

    # Assign the default if the above code fails
    $hostname = 'localhost' unless defined $hostname && 
      length($hostname) > 0;

    return $hostname;
  }

}


=head2 enableFacility

  $rv = enableFacility($name, $facility, $logLevel, $scope, @args);

This function enables the specified logging facility at the specified levels.
Each facility (or permutation of) is associated with an arbitrary name.
This name can be used to bypass log distribution and log only in the named
facility.

The following facilities are available within Paranoid:

  facility        description
  =====================================================
  stderr          prints messages to STDERR
  buffer          stores messages in a named buffer
  file            prints messages to a file
  syslog          sends message to the syslog daemon
  email           sends message to an e-mail recipient

If you have your own custom facility that complies with the Paranoid::Log
calling conventions you can pass this the name of the module (for example,
Log::Foo).  The first letter of the module will always be uppercased before
attempting to load it.

Log levels are modeled after syslog:

  log level       description
  =====================================================
  emerg, panic    system is unusable
  alert           action must be taken immediately
  crit            critical conditions
  err, error      error conditions
  warn, warning   warning conditions
  notice          normal but significant conditions
  info            informational
  debug           debug-level messages

If omitted level defaults to 'notice'.

Scope is defined with the following characters:

  character       definition
  =====================================================
  =               log only messages at this severity
  +               log only messages at this severity
                  or higher
  -               log only messages at this severity
                  or lower

If omitted scope defaults to '+'.

Only the first two arguments are mandatory.  What you put into the @args, and
whether you need it at all, will depend on the facility you're using.  The
facilities provided directly by B<Paranoid> are as follows:

  facility        arguments
  =====================================================
  stderr          none
  buffer          bufferSize (optional)
  file            filename
  syslog          none
  email           mailhost, recipient, sender (optional), 
                  subject (optional)

=cut

sub enableFacility ($$;$$@) {
  my $name          = shift;
  my $facility      = shift;
  my $logLevel      = shift;
  my $scope         = shift;
  my @args          = @_;
  my $larg          = defined $logLevel ? $logLevel : 'undef';
  my $sarg          = defined $scope ? $scope : 'undef';
  my @scopes        = qw(= + -);
  my $rv            = 0;

  # Validate arguments
  $logLevel = 'notice' unless defined $logLevel;
  $scope    = '+' unless defined $scope;
  croak "Invalid name was passed to enableFacility()" unless 
    defined $name;
  croak "Invalid log level was passed to enableFacility()" unless
    grep /^\Q$logLevel\E$/, @LEVELS;
  croak "Invalid scope was passed to enableFacility()" unless
    grep /^\Q$scope\E$/, @scopes;

  pdebug("entering w/($facility)($larg)($sarg)", 9);
  pIn();

  # Convert level synonyms
  $logLevel = _convertLevel($logLevel);

  # Add to named loggers
  $rv = _addLog($name, $facility, $logLevel, $scope, @args);

  # Initialize distribution
  initLogDist() if $rv;

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 disableFacility

  $rv = disableFacility($name)

Removes the specified logging facility from the configuration and
re-initializes the distribution processor.

=cut

sub disableFacility ($) {
  my $name          = shift;
  my $rv;

  croak "Invalid name was passed to enableFacility()" unless 
    defined $name;

  pdebug("entering w/($name)", 9);
  pIn();

  $rv = _delLog($name);
  initLogDist() if $rv;

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 plog

  $rv = plog($severity, $message);

This call logs the passed message to all facilities enabled at the specified
log level.

=cut

sub plog ($$) {
  my $severity    = shift;
  my $message     = shift;
  my $dref        = _getDistRef();
  my $msgtime     = time();
  my $rv          = 1;
  my ($lref, $sref);

  # Validate arguments
  croak "Invalid severity was passed to plog()" unless
    defined $severity && grep /^\Q$severity\E$/, @LEVELS;
  croak "Undefined or non-scalar value passed as the message to plog()"
    unless defined $message && ref($message) eq "";

  pdebug("entering w/($severity)($message)", 9);
  pIn();

  # Convert level synonyms
  $severity = _convertLevel($severity);

  # Trim message length
  $message = substr($message, 0, 2048);

  # Iterate over every entry in the severity array
  foreach $lref (@{ $$dref{$severity} }) {

    # Only process if the module is loaded
    if (_loadModule($$lref[1])) {
      if ($$lref[1] eq 'stderr') {
        $rv = perror($message) ? 1 : 0;
      } else {
        # Get a reference the appropriate sub
        $sref = _getLogRef($$lref[1]);
        $rv = defined $sref ? &$sref($msgtime, $severity, $message, @$lref) :
          0;
      }
    } else {
      $rv = 0;
    }
  }

#      } elsif ($$lref[1] eq 'email') {
#        $rv = 0 unless Paranoid::Log::Email::log($message, $msgtime);
#      }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 ptimestamp

  $ts = ptimestamp();

This function returns a syslog-style timestamp string for the current time.
You can optionally give it a value as returned by time() and the stamp will
be for that timme.

=cut

sub ptimestamp (;$) {
  my $utime   = shift;
  my @months  = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
  my @ctime;

  @ctime = defined $utime ? (localtime($utime)) : (localtime);

  return sprintf('%s %2d %02d:%02d:%02d', $months[ $ctime[4] ],
    @ctime[3,2,1,0]);
}

=head2 psyslog

  $rv = psyslog($severity, $message);

This function's name may be a bit misleading.  This does not cause the
message to be syslogged (that's the duty of the syslog facility), but rather
the message is logged in a syslog-style format according to the following
template:

  {timestamp} {hostname} {process}[{pid}]: {message}

You may want to use this if you're using, say, a file logging mechanism but
you still want the logs in a syslog-styled format.

=cut

sub psyslog ($$) {
  my $severity    = shift;
  my $message     = shift;
  my $timestamp   = ptimestamp();
  my $hostname    = _getHostname();
  my ($pname)     = ($0 =~ m#^(?:.+/)?([^/]+)$#);
  my $pid         = $$;
  my $rv;

  # Validate arguments
  croak "Invalid severity was passed to psyslog()" unless
    defined $severity;
  croak "Undefined or non-scalar value passed as the message to psyslog()"
    unless defined $message && ref($message) eq "";

  pdebug("entering w/($severity)($message)", 9);
  pIn();

  $rv = plog($severity, sprintf('%s %s %s[%d]: %s', $timestamp, $hostname,
    $pname, $pid, $message));

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head1 EXAMPLES

=head2 Enabling various facilities

  # STDERR facility
  $rv = enableFacility("console-err", "stderr", "warn", "+");

  # Log buffer w/100 message capacity
  $rv = enableFacility("buffer1", "buffer", "warn", "=", 100);

  # Log file (/var/log/app-debug.log)
  $rv = enableFacility("debug", "file", "warn", "=", 
    "/var/log/app-debug.log");

  # Syslog under mail facility
  $rv = enableFacility("mail", "syslog", "warn", "+");

  # E-mail critical or higher errs
  $rv = enableFacility("mail", "email", "crit", "+", "localhost",
    'root@localhost', undef, 'Critical Alert');

=cut

1;

=head1 HISTORY

None as of yet.

=head1 AUTHOR/COPYRIGHT

(c) 2005 Arthur Corliss (corliss@digitalmages.com)

=cut

