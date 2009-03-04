# Paranoid::Log::Email -- Log Facility Email for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Email.pm,v 0.7 2009/03/04 09:32:51 acorliss Exp $
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

package Paranoid::Log::Email;

use strict;
use warnings;
use vars qw($VERSION);
use Paranoid::Debug qw(:all);
use Carp;
use Net::SMTP;
use Net::Domain qw(hostfqdn);

($VERSION) = ( q$Revision: 0.7 $ =~ /(\d+(?:\.(\d+))+)/sm );

#####################################################################
#
# Module code follows
#
#####################################################################

sub init () {

    # Purpose:  Exists purely for compliance.
    # Returns:  True (1)
    # Usage:    init();

    return 1;
}

sub remove ($) {

    # Purpose:  Exists purely for compliance.
    # Returns:  True (1)
    # Usage:    init();

    return 1;
}

sub log ($$$$$$$$$;$$) {

    # Purpose:  Mails the passed message to the named recipient
    # Returns:  True (1) if successful, False (0) if not
    # Usage:    log($msgtime, $severity, $message, $name, $facility, $level,
    #               $scope);
    # Usage:    log($msgtime, $severity, $message, $name, $facility, $level,
    #               $scope, $mailhost);
    # Usage:    log($msgtime, $severity, $message, $name, $facility, $level,
    #               $scope, $mailhost, $recipient);
    # Usage:    log($msgtime, $severity, $message, $name, $facility, $level,
    #               $scope, $mailhost, $recipient, $sender);
    # Usage:    log($msgtime, $severity, $message, $name, $facility, $level,
    #               $scope, $mailhost, $recipient, $sender, $subject);

    my $msgtime   = shift;
    my $severity  = shift;
    my $message   = shift;
    my $name      = shift;
    my $facility  = shift;
    my $level     = shift;
    my $scope     = shift;
    my $mailhost  = shift;
    my $recipient = shift;
    my $sender    = shift;
    my $subject   = shift;
    my $m         = defined $mailhost ? $mailhost : 'undef';
    my $r         = defined $recipient ? $recipient : 'undef';
    my $s1        = defined $sender ? $sender : 'undef';
    my $s2        = defined $subject ? $subject : 'undef';
    my $rv        = 0;
    my ( $smtp, $hostname, $data );

    # Validate arguments
    croak 'Mandatory third argument must be a valid message'
        unless defined $message;

    pdebug(
        "entering w/($msgtime)($severity)($message)($name)"
            . "($facility)($level)($scope)($m)($r)($s1)($s2)",
        PDLEVEL1
    );
    pIn();

    # We need a mailhost and recipient at a minimum
    if ( defined $mailhost && defined $recipient ) {

        # Get the system hostname
        $hostname = hostfqdn();

        # Make sure something is set for the sender
        $sender = "$ENV{USER}\@$hostname" unless defined $sender;

        # Make sure something is set for the subject
        $subject = "ALERT from $ENV{USER}\@$hostname" unless defined $subject;

        # Compose the data block
        $data = << "__EOF__";
To:      @{[ ref($recipient) eq 'ARRAY' ? join(', ', @$recipient) : $recipient ]}
From:    $sender
Subject: $subject

This alert was sent out from $hostname by 
$ENV{USER} because of a log event which met or exceeded the 
$level level.  The message of this event is as follows:

$message

__EOF__

        pdebug( "sending to $recipient to $mailhost", PDLEVEL2 );

        # Try to open an SMTP connection
        if ( $smtp = Net::SMTP->new( $mailhost, Timeout => 30 ) ) {

            # Start the transaction
            if ( $smtp->mail($sender) ) {

                # Send to all recipients
                if ( ref $recipient eq 'ARRAY' ) {
                    foreach (@$recipient) {
                        Paranoid::ERROR =
                            pdebug( "server rejected recipient: $_",
                            PDLEVEL1 )
                            unless $smtp->to($_);
                    }
                } else {
                    Paranoid::ERROR =
                        pdebug( "server rejected recipient: $recipient",
                        PDLEVEL1 )
                        unless $smtp->to($recipient);
                }

                # Send the message
                $rv = $smtp->data($data);

                # Log the error
            } else {
                Paranoid::ERROR =
                    pdebug( "server rejected sender: $sender", PDLEVEL1 );
                $rv = 0;
            }

            # Close the connection
            $smtp->quit;

        } else {

            # Failed to connect to the server!
            Paranoid::ERROR =
                pdebug( "couldn't connect to server: $mailhost", PDLEVEL1 );
            $rv = 0;
        }

    } else {

        # Who the hell activated this facility without at least that?!
        Paranoid::ERROR = pdebug(
            'Message logged with e-mail facility, but we have '
                . 'neither a mailhost or a recipient to send to -- ignoring',
            PDLEVEL1
        );
        $rv = 0;
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub dump ($) {

    # Purpose:  Exists purely for compliance.
    # Returns:  True (1)
    # Usage:    init();

    return ();
}

1;

__END__

=head1 NAME

Paranoid::Log::Email - Log Facility Email

=head1 VERSION

$Id: Email.pm,v 0.7 2009/03/04 09:32:51 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Log;
  
  enableFacility('crit-alert', 'email', 'debug', '+', $mailhost, 
    $recipient);
  enableFacility('crit-alert', 'email', 'debug', '+', $mailhost, 
    [ @recipients ]);
  enableFacility('crit-alert', 'email', 'debug', '+', $mailhost, 
    $recipient, $sender, $subject);

=head1 DESCRIPTION

This module implements an e-mail transport for messages sent to the logger.
It supports one or more recipients as well as overriding the sender address
and subject line.  It also supports connecting to a remote mail server.

=head1 DEPENDENCIES

=over

=item o

L<Net::SMTP>

=item o

L<Net::Domain>

=item o

L<Paranoid::Debug>

=back

=head1 SUBROUTINES/METHODS

B<NOTE>:  Given that this module is not intended to be used directly nothing
is exported.

=head1 SEE ALSO

=over

=item o

L<Paranoid::Log>

=back

=head1 BUGS AND LIMITATIONS

No validation of any information, be it the mail server, recipient, or
anything else is done until a message actually needs to be sent.  Because of
this you may have no warning of any misconfigurations just by enabling the
facility.

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

