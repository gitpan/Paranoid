# Paranoid::Network -- Network functions for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Network.pm,v 0.68 2012/05/29 21:38:19 acorliss Exp $
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
use Paranoid::Network::Socket;
use Paranoid::Network::IPv4 qw(:all);
use Paranoid::Network::IPv6 qw(:all);
use Carp;

($VERSION) = ( q$Revision: 0.68 $ =~ /(\d+(?:\.(\d+))+)/sm );

@EXPORT    = qw(ipInNetwork hostInDomain extractIPs netIntersect);
@EXPORT_OK = qw(ipInNetwork hostInDomain extractIPs netIntersect);
%EXPORT_TAGS =
    ( all => [qw(ipInNetwork hostInDomain extractIPs netIntersect)], );

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
    my $i        = defined $ip ? $ip : 'undef';
    my @networks = grep {defined} @_;
    my $rv       = 0;
    my ( $family, @tmp );

    pdebug( "entering w/($i)(@networks)", PDLEVEL1 );
    pIn();

    # Validate arguments
    if ( defined $ip ) {

        # Extract IPv4 address from IPv6 encoding
        $ip =~ s/^::ffff:(@{[ IPV4REGEX ]})$/$1/smio;

        # Check for IPv6 support
        if ( has_ipv6() or $] >= 5.012 ) {

            pdebug( 'Found IPv4/IPv6 support', PDLEVEL2 );
            $family =
                  $ip =~ m/^@{[ IPV4REGEX ]}$/smo ? AF_INET()
                : $ip =~ m/^@{[ IPV6REGEX ]}$/smo ? AF_INET6()
                :                                   undef;

        } else {

            pdebug( 'Found only IPv4 support', PDLEVEL2 );
            $family = AF_INET()
                if $ip =~ m/^@{[ IPV4REGEX ]}$/smo;
        }
    }

    if ( defined $ip and defined $family ) {

        # Filter out non-family data from @networks
        @networks = grep {
            $family == AF_INET()
                ? m#^@{[ IPV4CIDRRGX ]}$#smo
                : m#^@{[ IPV6CIDRRGX ]}$#smo
        } @networks;

        pdebug( "networks to compare: @{[ join ', ', @networks ]}",
            PDLEVEL2 );

        # Start comparisons
        foreach (@networks) {
            if ($family == AF_INET()
                ? ipv4NetIntersect( $ip, $_ )
                : ipv6NetIntersect( $ip, $_ )
                ) {
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

sub extractIPs (@) {

    # Purpose:  Extracts IPv4/IPv6 addresses from arbitrary text.
    # Returns:  List containing extracted IP addresses
    # Usage:    @ips = extractIP($string1, $string2);

    my @strings = grep {defined} @_;
    my ( $string, @ips, $ip, @tmp, @rv );

    pdebug( "entering w/(@strings)", PDLEVEL1 );
    pIn();

    foreach $string (@strings) {

        # Look for IPv4 addresses
        @ips = ( $string =~ /(@{[ IPV4REGEX ]})/smog );

        # Validate them by filtering through inet_aton
        foreach $ip (@ips) {
            push @rv, $ip if defined inet_aton($ip);
        }

        # If Socket6 is present or we have Perl 5.14 or higher we'll check
        # for IPv6 addresses
        if ( has_ipv6() or $] >= 5.012 ) {

            @ips = ( $string =~ m/(@{[ IPV6REGEX ]})/smogix );

            # Filter out addresses with more than one ::
            @ips = grep { scalar(m/(::)/smg) <= 1 } @ips;

            # Validate remaining addresses with inet_pton
            foreach $ip (@ips) {
                push @rv, $ip
                    if defined inet_pton( AF_INET6(), $ip );
            }
        }
    }

    pOut();
    pdebug( "leaving w/rv: @rv)", PDLEVEL1 );

    return @rv;
}

sub netIntersect (@) {

    # Purpose:  Tests whether network address ranges intersect
    # Returns:  Integer, denoting whether an intersection exists, and what
    #           kind:
    #
    #               -1: destination range encompasses target range
    #                0: both ranges do not intersect at all
    #                1: target range encompasses destination range
    #
    # Usage:    $rv = netIntersect( $cidr1, $cidr2 );

    my $target = shift;
    my $dest   = shift;
    my $t      = defined $target ? $target : 'undef';
    my $d      = defined $dest ? $dest : 'undef';
    my $rv     = 0;

    pdebug( "entering w/$t, $d", PDLEVEL1 );
    pIn();

    if ( defined $target and defined $dest ) {
        if ( $target =~ m/^@{[ IPV4CIDRRGX ]}$/sm ) {
            $rv = ipv4NetIntersect( $target, $dest );
        } elsif ( $target =~ m/^@{[ IPV6CIDRRGX ]}$/smi ) {
            $rv = ipv6NetIntersect( $target, $dest )
                if has_ipv6()
                    or $] >= 5.012;
        } else {
            pdebug(
                "target string ($target) doesn't seem to match"
                    . 'an IP/network address',
                PDLEVEL1
                );
        }
    } else {
        pdebug( 'one or both arguments are not defined', PDLEVEL1 );
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

$Id: Network.pm,v 0.68 2012/05/29 21:38:19 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Network;

  $rv  = ipInNetwork($ip, @networks);
  $rv  = hostInDomain($host, @domains);
  @ips = extractIP($string1, $string2);
  $rv = netIntersect( $cidr1, $cidr2 );

=head1 DESCRIPTION

This modules contains functions that may be useful for network operations.
IPv6 is supported out of the box starting with Perl 5.14.  Earlier versions of
Perl will require L<Socket6(3)> installed as well.  If it is available this
module will use it automatically.

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

IPv6 is supported if the L<Socket6(3)> module is installed or you're running
Perl 5.14 or higher.  This routine will select the appropriate address family 
based on the IP you're testing and filter out the opposing address family in 
the list.

B<NOTE:>  IPv4 addresses encoded as IPv6 addresses, e.g.:

  ::ffff:192.168.0.5

are supported, however an IP address submitted in this format as the IP to
test for will be converted to a pure IPv4 address and compared only against
the IPv4 networks.  This is meant as a convenience to the developer supporting
dual-stack systems to avoid having to list IPv4 networks in the array twice
like so:

  ::ffff:192.168.0.0/120, 192.168.0.0/24

Just list IPv4 as IPv4, IPv6 as IPv6, and this routine will convert
IPv6-encoded IPv4 addresses automatically.  This would make the following test
return a true value:

  ipInNetwork( '::ffff:192.168.0.5', '192.168.0.0/24' );

but

  ipInNetwork( '::ffff:192.168.0.5', '::ffff:192.168.0.0/120' );

return a false value.  This may seem counter intuitive, but it simplifies
things in (my alternate) reality.

Please note that this automatic conversion only applies to the B<IP> argument,
not to any member of the network array.

=head2 hostInDomain

  $rv = hostInDomain($host, @domains);

This function checks the passed hostname (fully qualified) against each 
of the domains in the list and returns true if there's a match.  None of the
domains should have the preceding '.' (i.e., 'foo.com' rather than 
'.foo.com').

=head2 extractIPs

    @ips = extractIP($string1, $string2);

This function extracts IP addresses from arbitrary text.  If you have
L<Socket6(3)> installed or running Perl 5.14 or higher it will extract 
IPv6 addresses as well as IPv4 addresses.  This extracts only IP 
addresses, not network addresses in CIDR or dotted octet
notation.  In the case of the latter the netmask will be extracted as an
additional address.

B<NOTE:> in the interest of performance this function does only rough regex
extraction of IP-looking candidates, then runs them through B<inet_aton> (for
IPv4) and B<inet_pton> (for IPv6) to see if they successfully convert.  Even
with the overhead of B<Paranoid> (with debugging and I<loadModule> calls for
Socket6 and what-not) it seems that this is an order of a magnitude faster
than doing a pure regex extraction & validation of IPv6 addresses.

B<NOTE:> Like the B<ipInNetwork> function we filter out IPv4 addresses encoded
as IPv6 addresses since that address is already returned as a pure IPv4
address.

=head2 netIntersect

  $rv = netIntersect( $cidr1, $cidr2 );

This function is an IPv4/IPv6 agnostic wrapper for the B<ipv{4,6}NetIntersect>
functions provided by L<Paranoid::Network::IPv{4,6}> modules.  The return
value from which ever function called is passed on directly.  Passing this
function non-IP or undefined values simply returns a zero.

=head1 DEPENDENCIES

=over

=item o

L<Paranoid>

=item o

L<Paranoid::Network::Socket>

=item o

L<Paranoid::Network::IPv4>

=item o

L<Paranoid::Network::IPv6>

=back

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

