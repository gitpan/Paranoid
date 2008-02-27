# Paranoid::Network -- Network functions for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Network.pm,v 0.2 2008/01/23 06:49:38 acorliss Exp $
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

Paraniod::Network - Network functions for paranoid programs

=head1 MODULE VERSION

$Id: Network.pm,v 0.2 2008/01/23 06:49:38 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Network;

  $rv = ipInNetwork($ip, @networks);
  $rv = hostInDomain($host, @domains);

=head1 REQUIREMENTS

Paranoid

=head1 DESCRIPTION

This modules contains functions that may be useful for network operations.

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::Network;

use strict;
use warnings;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use Exporter;
use Paranoid::Debug;
use Socket;
use Carp;

($VERSION)    = (q$Revision: 0.2 $ =~ /(\d+(?:\.(\d+))+)/);

@ISA          = qw(Exporter);
@EXPORT       = qw(ipInNetwork hostInDomain);
@EXPORT_OK    = qw(ipInNetwork hostInDomain);
%EXPORT_TAGS  = (
  all => [qw(ipInNetwork hostInDomain)],
  );

#####################################################################
#
# Module code follows
#
#####################################################################

=head1 FUNCTIONS

=head2 ipInNetwork

  $rv = ipInNetwork($ip, @networks);

This function checks the passed IP against each of the networks 
or IPs in the list and returns true if there's a match.

=cut

sub ipInNetwork ($@) {
  my $ip        = shift;
  my @networks  = @_;
  my $rv        = 0;
  my ($bip, $bnet, $bmask);

  # Validate args
  croak "Undefined IP passed to ipInNetwork()" unless defined $ip;
  croak "Invalid IP ($ip) passed to ipInNetwork()" unless 
    $ip =~ m#^(?:(?:\d+\.){3})?\d+$#;

  pdebug("entering w/($ip)(@networks)", 9);
  pIn();

  # Filter out non-IP data from @networks
  @networks = grep {
    defined $_ && m#^(?:\d+\.){3}\d+(?:/(?:\d+|(?:\d+\.){3}\d+))?$#
    } @networks;

  # Start the comparisons
  if (scalar @networks) {

    # Convert IP to binary if necessary
    $bip = unpack('N', inet_aton($ip));
  
    # Compare against all networks
    foreach (@networks) {
  
      # Get the netmask
      #
      # No netmask means all ones
      if (m#^(?:\d+\.){3}\d+$#) {
        $bmask = 0xffffffff;
  
      # in IP notation
      } elsif (m#^(?:\d+\.){3}\d+/((?:\d+\.){3}\d+)$#) {
        $bmask = unpack('N', inet_aton($1));
  
      # in integer form
      } else {
        m#^(?:\d+\.){3}\d+/(\d+)$#;
        $bmask = 0xffffffff - ((2**(32 - $1)) - 1);
      }
  
      # Convert network to binary
      m#^((?:\d+\.){3}\d+)#;
      $bnet = unpack('N', inet_aton($1));
  
      # Compare ip/mask to net/mask
      if (($bip & $bmask) == ($bnet & $bmask)) {
        $rv = 1;
        last;
      }
    }
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 hostInDomain

  $rv = hostInDomain($host, @domains);

This function checks the passed hostname (fully qualified) against each 
of the domains in the list and returns true if there's a match.

=cut

sub hostInDomain ($@) {
  my $host    = shift;
  my @domains = @_;
  my $rv      = 0;
  my $domain;

  # Validate args
  croak "Undefined hostname passed to hostInDomain()" unless 
    defined $host;
  croak "Invalid hostname ($host) passed to hostInDomain()" unless 
    $host =~ /^(?:[\w\-]+\.)*[\w\-]+$/;

  pdebug("entering w/($host)(@domains)", 9);
  pIn();

  # Filter out non-domains
  @domains = grep {
    defined $_ && m/^(?:[\w\-]+\.)*[\w\-]+$/
    } @domains;

  # Start the comparison
  if (scalar @domains) {
    foreach $domain (@domains) {
      if ($host =~ /^(?:[\w\-]+\.)*\Q$domain\E$/i) {
        $rv = 1;
        last;
      }
    }
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

1;

=head1 HISTORY

None as of yet.

=head1 AUTHOR/COPYRIGHT

(c) 2005 Arthur Corliss (corliss@digitalmages.com)

=cut

