# Paranoid::Log::Email -- Log Facility Email for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Email.pm,v 0.6 2008/08/28 06:39:53 acorliss Exp $
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

Paranoid::Log::Email - Log Facility Email

=head1 MODULE VERSION

$Id: Email.pm,v 0.6 2008/08/28 06:39:53 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Log::Email;

  $rv = init();
  $rv = remove($name);

  $rv = log($msgtime, $severity, $message, $name, $facility, $level, $scope,
            $mailhost, $recipient, $sender, $subject);

=head1 REQUIREMENTS

=over

=item o

Paranoid::Debug

=item o

Net::SMTP

=back

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

package Paranoid::Log::Email;

use strict;
use warnings;
use vars qw($VERSION);
use Paranoid::Debug;
use Carp;
use Net::SMTP;
use Net::Domain qw(hostfqdn);

($VERSION)    = (q$Revision: 0.6 $ =~ /(\d+(?:\.(\d+))+)/);

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
            $mailhost, $recipient, $sender, $subject);

This function adds another log message to the log file.  This is 
not meant to be used directly.  Please use the B<Paranoid::Log> module.  Any
errors which occur during the e-mail transaction are stored in
B<Paranoid::ERROR>.

=cut

sub log($$$$$$$$$;$$) {
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
  my $m         = defined $mailhost  ? $mailhost  : 'undef';
  my $r         = defined $recipient ? $recipient : 'undef';
  my $s1        = defined $sender    ? $sender    : 'undef';
  my $s2        = defined $subject   ? $subject   : 'undef';
  my $rv        = 0;
  my ($smtp, $hostname, $data);

  # Validate arguments
  croak "Mandatory third argument must be a valid message" unless defined
    $message;

  pdebug("entering w/($msgtime)($severity)($message)($name)" .
    "($facility)($level)($scope)($m)($r)($s1)($s2)", 9);
  pIn();

  # Only try if the mailhost/sender is defined
  if (defined $mailhost && defined $recipient) {

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

    pdebug("sending to $recipient to $mailhost", 10);

    # Try to open an SMTP connection
    if ($smtp = Net::SMTP->new($mailhost, Timeout => 30)) {

      # Start the transaction
      if ($smtp->mail($sender)) {

        # Send to all recipients
        if (ref($recipient) eq 'ARRAY') {
          foreach (@$recipient) { 
            Paranoid::ERROR = pdebug("server rejected recipient: $_", 9)
             unless $smtp->to($_) };
        } else {
          Paranoid::ERROR = pdebug("server rejected recipient: $recipient", 9)
            unless $smtp->to($recipient);
        }

        # Send the message
        $rv = $smtp->data($data);

      # Log the error
      } else {
        Paranoid::ERROR = pdebug("server rejected sender: $sender", 9);
      }

      # Close the connection
      $smtp->quit;
    } else {
      Paranoid::ERROR = pdebug("couldn't connect to server: $mailhost", 9);
    }
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

sub dump($) {
  # This function is present only for compliance.
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

