# Paranoid::Log::Syslog -- Log Facility Syslog for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Syslog.pm,v 0.81 2009/03/05 00:09:34 acorliss Exp $
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

package Paranoid::Log::Syslog;

use 5.006;

use strict;
use warnings;
use vars qw($VERSION);
use Paranoid::Debug;
use Unix::Syslog qw(:macros :subs);
use Carp;

($VERSION) = ( q$Revision: 0.81 $ =~ /(\d+(?:\.(\d+))+)/sm );

#####################################################################
#
# Module code follows
#
#####################################################################

sub _setIdent (;$) {

    # Purpose:  Returns a name for use as the ident field.  If you don't want
    #           the process command as that you can pass an optional name to
    #           use instead.
    # Returns:  String
    # Usage:    $ident = _setIdent();
    # Usage:    $ident = _setIdent($name);

    my $name = shift;

    # Use $0 by default
    $name = $0 unless defined $name;

    # Strip path
    $name =~ s#^.*/##sm;

    return $name;
}

sub init (;@) {

    # Purpose:  Exists purely for compliance.
    # Returns:  True (1)
    # Usage:    init();

    return 1;
}

sub _transFacility ($) {

    # Purpose:  Translates the string log facilities into the syslog constants
    # Returns:  Constant scalar value
    # Usage:    $facility = _transFacility($facilityName);

    my $f     = lc shift;
    my %trans = (
        authpriv => LOG_AUTHPRIV,
        auth     => LOG_AUTHPRIV,
        cron     => LOG_CRON,
        daemon   => LOG_DAEMON,
        ftp      => LOG_FTP,
        kern     => LOG_KERN,
        local0   => LOG_LOCAL0,
        local1   => LOG_LOCAL1,
        local2   => LOG_LOCAL2,
        local3   => LOG_LOCAL3,
        local4   => LOG_LOCAL4,
        local5   => LOG_LOCAL5,
        local6   => LOG_LOCAL6,
        local7   => LOG_LOCAL7,
        lpr      => LOG_LPR,
        mail     => LOG_MAIL,
        news     => LOG_NEWS,
        syslog   => LOG_SYSLOG,
        user     => LOG_USER,
        uucp     => LOG_UUCP,
    );

    return exists $trans{$f} ? $trans{$f} : undef;
}

sub _transLevel ($) {

    # Purpose:  Translates the passed log level string into the syslog
    #           constant
    # Returns:  Constant scalar value
    # Usage:    $level = _transLevel($levelName);

    my $l     = lc shift;
    my %trans = (
        debug   => LOG_DEBUG,
        info    => LOG_INFO,
        notice  => LOG_NOTICE,
        warn    => LOG_WARNING,
        warning => LOG_WARNING,
        err     => LOG_ERR,
        crit    => LOG_CRIT,
        alert   => LOG_ALERT,
        emerg   => LOG_EMERG,
        error   => LOG_ERR,
    );

    return exists $trans{$l} ? $trans{$l} : undef;
}

{
    my $sysopened = 0;

    sub _openSyslog (;$$) {

        # Purpose:  If the syslogger hasn't been opened yet it opens it,
        #           otherwise exits cleanly.
        # Returns:  True (1) if successful,
        #           False (0) if there are any errors
        # Usage:    $rv = _openSyslog();
        # Usage:    $rv = _openSyslog($ident);
        # Usage:    $rv = _openSyslog($ident, $facility);

        my $ident    = shift;
        my $facility = shift;
        my $i        = defined $ident ? $ident : 'undef';
        my $f        = defined $facility ? $facility : 'undef';

        pdebug( "entering w/($i)($f)", PDLEVEL2 );
        pIn();

        # Open a handle to the syslog daemon
        unless ($sysopened) {

            # Make sure both values are set
            $ident = _setIdent($ident);
            $facility = 'user' unless defined $facility;

            # Validate the facility
            croak 'Can\'t open handle to syslogger with an invalid facility: '
                . "$facility\n"
                unless defined( $facility = _transFacility($facility) );

            # Open the logger
            openlog $ident, LOG_CONS | LOG_NDELAY | LOG_PID, $facility;
            $sysopened = 1;

            # TODO: trap return value of openlog?
        }

        pOut();
        pdebug( "leaving w/rv: $sysopened", PDLEVEL2 );

        return $sysopened;
    }

    sub remove (;$) {

        # Purpose:  Closes the syslogger
        # Returns:  True (1)
        # Usage:    remove();

        pdebug( 'entering', PDLEVEL2 );

        closelog();
        $sysopened = 0;

        pdebug( 'leaving w/rv: 1', PDLEVEL2 );

        return 1;
    }
}

sub log ($$$$$$$) {

    # Purpose:  Logs the passed message to the named file
    # Returns:  Return value of print()
    # Usage:    log($msgtime, $severity, $message, $name, $facility, $level,
    #               $scope);
    # Usage:    log($msgtime, $severity, $message, $name, $facility, $level,
    #               $scope, $progName);

    my $msgtime  = shift;
    my $severity = shift;
    my $message  = shift;
    my $name     = shift;
    my $facility = shift;
    my $level    = shift;
    my $scope    = shift;
    my $rv       = 0;

    # Set defaults on optional args
    $name     = 'user'   unless defined $name;
    $severity = 'notice' unless defined $severity;

    # Validate arguments
    croak 'Mandatory second argument must be a valid severity'
        unless defined _transLevel($severity);
    croak 'Mandatory third argument must be a valid message'
        unless defined $message;
    croak 'Mandatory fourth argument must be a valid syslog facility'
        unless defined _transFacility($name);

    pdebug(
        "entering w/($msgtime)($severity)($message)($name)"
            . "($facility)($level)($scope)",
        PDLEVEL1
    );
    pIn();

    # TODO:  Make sure prog name works?

    # Make sure the logger is ready and log the message
    if ( _openSyslog( undef, $name ) ) {
        syslog _transLevel($severity), '%s', $message;
        $rv = 1;
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub dump() {

    # Purpose:  Exists purely for compliance.
    # Returns:  True (1)
    # Usage:    init();

    return ();
}

1;

__END__

=head1 NAME

Paranoid::Log::Syslog - Log Facility Syslog

=head1 VERSION

$Id: Syslog.pm,v 0.81 2009/03/05 00:09:34 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Log;
  
  enableFacility('local3', 'syslog', 'debug', '+');
  enableFacility('local3', 'syslog', 'debug', '+', 'my-daemon');

=head1 DESCRIPTION

This module implements UNIX syslog support for logging purposes.  Which should
seem natural given that the entire B<Paranoid::Log> API is modeled closely
after it.

=head1 SUBROUTINES/METHODS

B<NOTE>:  Given that this module is not intended to be used directly nothing
is exported.

=head1 DEPENDENCIES

=over

=item o

L<Paranoid::Debug>

=item o

L<Unix::Syslog>

=back

=head1 BUGS AND LIMITATIONS

Because we're keeping a connection to the syslogger open we don't support
enabling multiple facilities that log as different idents, etc.  The first
syslog facility that gets activated will set those parameters.

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

