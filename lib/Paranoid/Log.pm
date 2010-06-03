# Paranoid::Log -- Log support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Log.pm,v 0.14 2010/06/03 19:03:32 acorliss Exp $
#
#    This software is licensed under the same terms as Perl, itself.
#    Please see http://dev.perl.org/licenses/ for more information.
#
#####################################################################

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::Log;

use 5.006;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS);
use base qw(Exporter);
use Paranoid::Debug qw(:all);
use Paranoid::Module;
use Paranoid::Input;
use Carp;

($VERSION) = ( q$Revision: 0.14 $ =~ /(\d+(?:\.(\d+))+)/sm );

@EXPORT = qw(enableFacility   disableFacility   plog
    psyslog);
@EXPORT_OK = qw(enableFacility   disableFacility   clearLogDist
    initLogDist      plog              ptimestamp
    psyslog);
%EXPORT_TAGS = (
    all => [
        qw(enableFacility   disableFacility   clearLogDist
            initLogDist      plog              ptimestamp
            psyslog)
        ],
        );

use constant PLDEBUG  => 0;
use constant PLINFO   => 1;
use constant PLNOTICE => 2;
use constant PLWARN   => 3;
use constant PLERR    => 4;
use constant PLCRIT   => 5;
use constant PLALERT  => 6;
use constant PLEMERG  => 7;

use constant MAXMSGLNGTH => 2048;

#####################################################################
#
# Module code follows
#
#####################################################################

{

    my %loaded  = ();    # module => loaded (boolean)
    my %logRefs = ();    # module => log sub ref
    my @dist;            # modules to distribute to by log level

    # This has consists of the name/array key/value pairs.  Each associated
    # array consists of the following entries:
    #        [ $facility, $level, $scope, @optionalArgs].
    my %loggers = ();

    sub _convertLevel ($) {

        # Purpose:  Converts syslog severity level synonyms to the ones used
        #           internally
        # Returns:  Integer if a valid log level was passed, undef if not
        # Usage:    $level = _convertLevel($level);

        my $level = shift;

        return
              $level eq 'debug'     ? PLDEBUG
            : $level eq 'info'      ? PLINFO
            : $level eq 'notice'    ? PLNOTICE
            : $level eq 'warn'      ? PLWARN
            : $level eq 'warning'   ? PLWARN
            : $level eq 'err'       ? PLERR
            : $level eq 'error'     ? PLERR
            : $level eq 'crit'      ? PLCRIT
            : $level eq 'critical'  ? PLCRIT
            : $level eq 'alert'     ? PLALERT
            : $level eq 'emerg'     ? PLEMERG
            : $level eq 'emergency' ? PLEMERG
            : $level eq 'panic'     ? PLEMERG
            :                         undef;
    }

    sub _loadModule ($) {

        # Purpose:  Loads the requested module if it hasn't been already.
        #           Attempts to first load the module as a name relative to
        #           Paranoid::Log, otherwise by itself.
        # Returns:  True (1) if load was successful,
        #           False (0) if there are any errors
        # Usage:    $rv = _loadModule($module);

        my $module = shift;
        my $mname  = ucfirst $module;
        my ( $sref, $rv );

        pdebug( "entering w/($module)", PDLEVEL2 );
        pIn();

        # First attempt to load module under Paranoid::Log

        # Return the status of the requested module if it was already
        # autoloaded.

        # Was module already loaded (or a load attempted)?
        if ( exists $loaded{$module} ) {

            # Yep, so return module status
            $rv = $loaded{$module};

        } else {

            # Nope, so let's try to load it.
            #
            # Is the module name taint-safe?
            if ( detaint( $mname, 'filename', \$mname ) ) {

                # Yep, so try to load relative to Paranoid::Log
                $rv =
                    $mname eq 'Stderr' ? 1
                    : loadModule( "Paranoid::Log::$mname", '' )
                    && eval "Paranoid::Log::${mname}::init();"
                    && eval "\$sref = \\&Paranoid::Log::${mname}::log;" ? 1
                    :                                                     0;

                # If that failed, try to load it directly
                unless ($rv) {
                    $rv =
                        (      loadModule( $mname, '' )
                            && eval "${mname}::init();"
                            && eval "\$sref = \\&${mname}::log;" ) ? 1 : 0;
                }

                # Cache & report the results
                $loaded{$module} = $rv;
                $logRefs{$module} = $sref if defined $sref;
                if ($rv) {
                    pdebug( "successfully loaded log module for $module",
                        PDLEVEL3 );
                } else {
                    Paranoid::ERROR =
                        pdebug( "failed to load log module for $module",
                        PDLEVEL1 );
                }

            } else {

                # Module name failed detainting -- report
                Paranoid::ERROR =
                    pdebug( 'failed to detaint module name', PDLEVEL1 );
                $rv = 0;
            }
        }

        pOut();
        pdebug( "leaving w/rv: $rv", PDLEVEL2 );

        return $rv;
    }

    sub _addLogger ($$$$;@) {

        # Purpose:  Adds a named logger to our loggers hash.
        # Returns:  True (1) if successful,
        #           False (0) if there are any errors
        # Usage:    $rv = _addLogger($name, $level, $scope);

        my ( $name, $facility, $level, $scope, @args ) = @_;
        my $rv     = 0;
        my @scopes = qw(= + - !);
        my ( $ilevel, $iscope );

        pdebug( "entering w/($name)($facility)($level)($scope)",
            PDLEVEL3 );
        pIn();

        # Validate log level
        $ilevel = _convertLevel($level);
        Paranoid::ERROR =
            pdebug( "Invalid log level specified: $level", PDLEVEL1 )
            unless defined $ilevel;

        # Validate scope
        $iscope = scalar grep /^\Q$scope\E$/sm, @scopes;
        Paranoid::ERROR =
            pdebug( "Invalid log scope specified: $scope", PDLEVEL1 )
            unless $iscope;

        # Make sure the module can be loaded if the log level was valid
        $rv = _loadModule( $facility )
            if defined $ilevel
                and $iscope;

        # Make sure the log entry is uniqe
        if ($rv) {
            if ( exists $loggers{$name} ) {
                Paranoid::ERROR =
                    pdebug( "a logger for $name already exists", PDLEVEL1 );
                $rv = 0;
            } else {
                $loggers{$name} = [ $facility, $ilevel, $scope, @args ];
                $rv = 1;
            }
        }

        pOut();
        pdebug( "leaving w/rv: $rv", PDLEVEL3 );

        return $rv;
    }

    sub _delLog ($) {

        # Purpose:  Deletes a named logger from the hash.
        # Returns:  True (1)
        # Usage:    _delLog($name);

        my $name = shift;

        pdebug( "deleting $name logger", PDLEVEL3 );
        delete $loggers{$name} if exists $loggers{$name};

        return 1;
    }

    sub initLogDist () {

        # Purpose:  Goes through all named loggers and registers them at all
        #           the applicable levels.
        # Returns:  True (1)
        # Usage:    initLogDist();

        my @logNames = keys %loggers;
        my ( $logger, $level, $scope, @expanded );

        pdebug( 'entering', PDLEVEL1 );
        pIn();

        # clear @dist
        @dist = ();

        # Populate each log level applicable to each named logger
        foreach $logger (@logNames) {
            pdebug( "processing $logger", PDLEVEL2 );
            ( $level, $scope ) = @{ $loggers{$logger} }[ 1, 2 ];

            # Expand the list of levels according to the scope
            @expanded = ();
            if ( $scope eq '=' ) {
                push @expanded, $level;
            } elsif ( $scope eq '-' ) {
                while ( $level >= PLDEBUG ) { push @expanded, $level-- }
            } elsif ( $scope eq '+' ) {
                while ( $level <= PLEMERG ) { push @expanded, $level++ }
            } elsif ( $scope eq '!' ) {
                foreach ( PLDEBUG .. PLEMERG ) {
                    next if $level == $_;
                    push @expanded, $_;
                }
            }
            pdebug( "adding $logger to levels " . join( ',', @expanded ),
                PDLEVEL3 );

            # Add them to @dist
            foreach $level (@expanded) {
                $dist[$level] = [] unless defined $dist[$level];
                push @{ $dist[$level] }, [ $logger, @{ $loggers{$logger} } ];
            }
        }

        pOut();
        pdebug( 'leaving', PDLEVEL1 );

        return 1;
    }

    my $hostname;

    sub _getHostname () {

        # Purpose:  Returns the hostname, defaulting to localhost if
        #           /bin/hostname is unusable
        # Returns:  Hostname
        # Usage:    $hostname = _getHostname();

        my $fd;

        # Return cached result
        return $hostname if defined $hostname;

        # Get the current hostname
        if ( -x '/bin/hostname' ) {
            if ( open $fd, '-|', '/bin/hostname' ) {
                chomp( $hostname = <$fd> );
                close $fd;
            }
        }

        # Assign the default if the above code fails
        $hostname = 'localhost'
            unless defined $hostname and length $hostname;

        return $hostname;
    }

    sub enableFacility ($$;$$@) {

        # Purpose:  Enables the requested facilities at the specified levels
        # Returns:  True (1) if the facility is available for use,
        #           False (0) if there are any errors
        # Usage:    $rv = enableFacility($name, $facility, $logLevel,
        #               $scope, @args);

        my ( $name, $facility, $level, $scope, @args ) = @_;
        my $larg = defined $level ? $level : 'undef';
        my $sarg = defined $scope ? $scope : 'undef';
        my $rv   = 0;

        # Validate arguments
        croak 'Mandatory first argument must be a defined name'
            unless defined $name;
        croak 'Mandatory second argument must be a defined log facility'
            unless defined $facility;

        pdebug( "entering w/($name)($facility)($larg)($sarg)", PDLEVEL1 );
        pIn();

        # Set defaults for optional arguments that were left undefined
        $level = 'notice' unless defined $level;
        $scope = '+'      unless defined $scope;

        # Add to named loggers
        $rv = _addLogger( $name, $facility, $level, $scope, @args );

        # Initialize distribution
        initLogDist() if $rv;

        pOut();
        pdebug( "leaving w/rv: $rv", PDLEVEL1 );

        return $rv;
    }

    sub disableFacility ($) {

        # Purpose:  Disables and removes a facility from use.
        # Returns:  True (1) if the facility was successfully removed,
        #           False (0) if there are any errors
        # Usage:    $rv = disableFacility($name);

        my $name = shift;
        my $rv;

        croak 'Mandatory first argument must be a valid name'
            unless defined $name;

        pdebug( "entering w/($name)", PDLEVEL1 );
        pIn();

        $rv = _delLog($name);
        initLogDist() if $rv;

        pOut();
        pdebug( "leaving w/rv: $rv", PDLEVEL1 );

        return $rv;
    }

    sub plog ($$) {

       # Purpose:  Logs the message to all facilities registered at that level
       # Returns:  True (1) if the message was succesfully logged,
       #           False (0) if there are any errors
       # Usage:    $rv = plog($severity, $message);

        my $level   = shift;
        my $message = shift;
        my $msgtime = time;
        my $larg    = defined $level ? $level : 'undef';
        my $marg    = defined $message ? $message : 'undef';
        my $rv      = 1;
        my ( $ilevel, $logger, $sref );

        pdebug( "entering w/($larg)($marg)", PDLEVEL1 );
        pIn();

        # Validate level and message
        $ilevel = _convertLevel($level);
        $rv = 0 unless defined $message and defined $ilevel;

        if ($rv) {

            # Trim message length to traditional max syslog lengths
            $message = substr $message, 0, MAXMSGLNGTH;

            # Iterate over the @dist level
            if ( defined $dist[$ilevel] ) {

                # Iterate over each logger
                foreach $logger ( @{ $dist[$ilevel] } ) {
                    if ( $$logger[1] eq 'stderr' ) {

                        # Special handling for STDERR
                        $rv = perror($message) ? 1 : 0;

                    } else {

                        # Get the sub ref for the logger
                        $sref = $logRefs{ $$logger[1] };
                        $rv =
                            defined $sref
                            ? &$sref( $msgtime, $level, $message, @$logger )
                            : 0;
                    }
                }
            }

        } else {

            # Report error
            Paranoid::ERROR =
                pdebug( "invalid log level ($larg) or message ($marg)",
                PDLEVEL1 );
            $rv = 0;
        }

        pOut();
        pdebug( "leaving w/rv: $rv", PDLEVEL1 );

        return $rv;
    }
}

sub ptimestamp (;$) {

    # Purpose:  Returns a syslog-stype timestamp string for the current or
    #           passed time
    # Returns:  String
    # Usage:    $timestamp = ptimestamp();
    # Usage:    $timestamp = ptimestamp($epoch);

    my $utime  = shift;
    my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my @ctime;

    @ctime = defined $utime ? ( localtime $utime ) : (localtime);

    return sprintf
        '%s %2d %02d:%02d:%02d',
        $months[ $ctime[4] ],
        @ctime[ 3, 2, 1, 0 ];
}

sub psyslog ($$) {

    # Purpose:  Calls plog with a syslog-style entry prepended to the message
    # Returns:  The return value of the plog call
    # Usage:    $rv = psyslog($severity, $message);

    my $severity  = shift;
    my $message   = shift;
    my $timestamp = ptimestamp();
    my $hostname  = _getHostname();
    my ($pname) = ( $0 =~ m#^(?:.+/)?([^/]+)$#sm );
    my $pid = $$;
    my $rv;

    # Validate arguments
    croak 'Mandatory first argument must be a valid severity'
        unless defined $severity;
    croak 'Mandatory second argument must be a defined message'
        unless defined $message && ref $message eq '' && length $message;

    pdebug( "entering w/($severity)($message)", PDLEVEL1 );
    pIn();

    $rv = plog( $severity, sprintf '%s %s %s[%d]: %s',
        $timestamp, $hostname, $pname, $pid, $message );

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

1;

__END__

=head1 NAME

Paranoid::Log - Log Functions

=head1 VERSION

$Id: Log.pm,v 0.14 2010/06/03 19:03:32 acorliss Exp $

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

=head1 SYMBOL TAG SETS

By default, only the following are exported:

  enableFacility
  disableFacility
  plog
  psyslog

You can get everything using B<:all>, including:

  clearLogDist 
  initLogDist
  ptimestamp

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

=head1 SUBROUTINES/METHODS

=head2 clearLogDist

  clearLogDist();

This empties all enabled loggers from the distribution processor.  It
doesn't erase any named logging facilities already put into place, simply
takes out of the distribution system so no further log entries will be
processed.

This can be used to temporarily halt all logging.

=head2 initLogDist

  initLogDist();

This goes through the list of named loggers and sets up the distribution
processor to feed them the applicable log entries as they come in.

This can be used to re-enable logging.

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
  emerg, panic,   system is unusable
  emergency
  alert           action must be taken immediately
  crit, critical  critical conditions
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
  !               log at all levels but this severity

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

=head2 disableFacility

  $rv = disableFacility($name);

Removes the specified logging facility from the configuration and
re-initializes the distribution processor.

=head2 plog

  $rv = plog($severity, $message);

This call logs the passed message to all facilities enabled at the specified
log level.

=head2 ptimestamp

  $ts = ptimestamp();

This function returns a syslog-style timestamp string for the current time.
You can optionally give it a value as returned by time() and the stamp will
be for that timme.

=head2 psyslog

  $rv = psyslog($severity, $message);

This function's name may be a bit misleading.  This does not cause the
message to be syslogged (that's the duty of the syslog facility), but rather
the message is logged in a syslog-style format according to the following
template:

  {timestamp} {hostname} {process}[{pid}]: {message}

You may want to use this if you're using, say, a file logging mechanism but
you still want the logs in a syslog-styled format.  More often than not,
though, you do not want to use this function.

=head1 DEPENDENCIES

=over

=item o

L<Paranoid::Debug>

=item o

L<Paranoid::Input>

=item o

L<Paranoid::Module>

=back

=head1 EXAMPLES

The following example provides the following behavior:  debug messages go to a
file, notice & above messages go to syslog, and critical and higher messages
also go to console and e-mail.

  # Set up the logging facilities
  enableFacility("debug", "file", "debug", "=", 
    "/var/log/myapp-debug.log");
  enableFacility("daemon", "syslog", "notice", "+", "myapp");
  enableFacility("console-err", "stderr", "critical", "+");
  enableFacility("smtp-err", "email", "critical", "+", 
    "localhost", "root\@localhost", "myapp\@localhost", 
    "MyApp Critical Alert");

  # Log some messages
  #
  # Since this is only going to the debug log, we'll use psyslog 
  # so we get the timestamps, etc.
  psyslog("debug", "Starting application");

  # Log a notification
  plog("notice", "Uh, something happened...");

  # Log a critical error
  plog("emerg", "Ack! <choke... silence>");

=head1 SEE ALSO

=over

=item o

L<Paranoid::Log::Buffer>

=item o

L<Paranoid::Log::Email>

=item o

L<Paranoid::Log::File>

=item o

L<Paranoid::Log::Syslog>

=back

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

