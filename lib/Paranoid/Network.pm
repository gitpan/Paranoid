# Paranoid::Network -- Network functions for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Network.pm,v 0.6 2009/03/04 09:32:51 acorliss Exp $
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

package Paranoid::Network;

use 5.006;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS);
use base qw(Exporter);
use Paranoid::Debug qw(:all);
use Socket;
use Carp;

($VERSION) = ( q$Revision: 0.6 $ =~ /(\d+(?:\.(\d+))+)/sm );

@EXPORT      = qw(ipInNetwork hostInDomain);
@EXPORT_OK   = qw(ipInNetwork hostInDomain);
%EXPORT_TAGS = ( all => [qw(ipInNetwork hostInDomain)], );

#####################################################################
#
# Module code follows
#
#####################################################################

sub ipInNetwork ($@) {

    # Purpose:  Checks to see if the IP occurs in the passed list of IPs and
    #           networks
    # Returns:  True (1) if the IP occurs, False (0) otherwise
    # Usage:    $rv = ipInNetwork($ip, @networks);

    my $ip       = shift;
    my @networks = @_;
    my $rv       = 0;
    my ( $bip, $bnet, $bmask );

    # Validate arguments
    croak 'Mandatory first argument must be a defined IP address'
        unless defined $ip && $ip =~ m#^(?:(?:\d+\.){3})?\d+$#sm;

    pdebug( "entering w/($ip)(@networks)", PDLEVEL1 );
    pIn();

    # Filter out non-IP data from @networks
    @networks = grep {
        defined $_
            && m#^(?:\d+\.){3}\d+(?:/(?:\d+|(?:\d+\.){3}\d+))?$#sm
    } @networks;

    # Start the comparisons
    if (@networks) {

        # Convert IP to binary if necessary
        $bip = unpack 'N', inet_aton($ip);

        # Compare against all networks
        foreach (@networks) {

            # Get the netmask
            if (m#^(?:\d+\.){3}\d+$#sm) {

                # No netmask means all ones
                $bmask = 0xffffffff;

            } elsif (m#^(?:\d+\.){3}\d+/((?:\d+\.){3}\d+)$#sm) {

                # in IP notation
                $bmask = unpack 'N', inet_aton($1);

            } else {

                # in integer form
                m#^(?:\d+\.){3}\d+/(\d+)$#sm;
                $bmask = 0xffffffff - ( ( 2**( 32 - $1 ) ) - 1 );
            }

            # Convert network to binary
            m#^((?:\d+\.){3}\d+)#sm;
            $bnet = unpack 'N', inet_aton($1);

            # Compare ip/mask to net/mask
            if ( ( $bip & $bmask ) == ( $bnet & $bmask ) ) {
                $rv = 1;
                last;
            }
        }
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub hostInDomain ($@) {

    # Purpose:  Checks to see if the host occurs in the list of domains
    # Returns:  True (1) if the host occurs, False (0) otherwise
    # Usage:    $rv = hostInDomain($hostname, @domains);

    my $host    = shift;
    my @domains = @_;
    my $rv      = 0;
    my $domain;

    # Validate arguments
    croak 'Mandatory first argument must be a defined and valid hostname'
        unless defined $host && $host =~ /^(?:[\w\-]+\.)*[\w\-]+$/sm;

    pdebug( "entering w/($host)(@domains)", PDLEVEL1 );
    pIn();

    # Filter out non-domains
    @domains = grep { defined $_ && m/^(?:[\w\-]+\.)*[\w\-]+$/sm } @domains;

    # Start the comparison
    if (@domains) {
        foreach $domain (@domains) {
            if ( $host =~ /^(?:[\w\-]+\.)*\Q$domain\E$/smi ) {
                $rv = 1;
                last;
            }
        }
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

1;

__END__

=head1 NAME

Paranoid::Network - Network functions for paranoid programs

=head1 VERSION

$Id: Network.pm,v 0.6 2009/03/04 09:32:51 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Network;

  $rv = ipInNetwork($ip, @networks);
  $rv = hostInDomain($host, @domains);

=head1 DESCRIPTION

This modules contains functions that may be useful for network operations.

=head1 SUBROUTINES/METHODS

=head2 ipInNetwork

  $rv = ipInNetwork($ip, @networks);

This function checks the passed IP against each of the networks 
or IPs in the list and returns true if there's a match.  The list of networks
can be either individual IP address or network addresses in CIDR notation or
with full netmasks:

  @networks = qw(127.0.0.1 
                 192.168.0.0/24 
                 172.16.12.0/255.255.240.0);

=head2 hostInDomain

  $rv = hostInDomain($host, @domains);

This function checks the passed hostname (fully qualified) against each 
of the domains in the list and returns true if there's a match.  None of the
domains should have the preceding '.' (i.e., 'foo.com' rather than 
'.foo.com').

=head1 DEPENDENCIES

=over

=item o

L<Paranoid>

=item o

L<Socket>

=back

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

