# Paranoid::Network -- Network functions for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Network.pm,v 0.67 2011/12/20 03:00:42 acorliss Exp $
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
use Carp;

($VERSION) = ( q$Revision: 0.67 $ =~ /(\d+(?:\.(\d+))+)/sm );

@EXPORT      = qw(ipInNetwork hostInDomain extractIPs);
@EXPORT_OK   = qw(ipInNetwork hostInDomain extractIPs);
%EXPORT_TAGS = ( all => [qw(ipInNetwork hostInDomain extractIPs)], );

use constant CHUNK       => 32;
use constant IPV6CHUNKS  => 4;
use constant MAXIPV4CIDR => 32;
use constant MAXIPV6CIDR => 128;
use constant MASK        => 0xffffffff;
use constant IP4REGEX    => qr/(?:\d{1,3}\.){3}\d{1,3}/sm;
use constant IP6REGEX    => qr/
                            :(?::[abcdef\d]{1,4}){1,7}                 | 
                            [abcdef\d]{1,4}(?:::?[abcdef\d]{1,4}){1,7} | 
                            (?:[abcdef\d]{1,4}:){1,7}:
                            /smix;

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
    my $oip      = $ip;
    my ( $bip, $bnet, $bmask, $family, @tmp, $irv );

    # Validate arguments
    if ( defined $ip ) {

        # Test for an IPv4 address
        if ( $ip =~ m/^@{[ IP4REGEX ]}$/smo and defined inet_aton($ip) ) {
            $family = AF_INET();
        } else {

            # If Socket6 is present or we have Perl 5.14 or higher we'll check
            # for IPv6 addresses
            if ( has_ipv6() or $] >= 5.012 ) {

                if ( defined inet_pton( AF_INET6(), $ip ) ) {

                    # Convert IPv6-encoded IPv4 addresses to pure IPv4
                    if ( $ip =~ m/^::ffff:(@{[ IP4REGEX ]})$/smio ) {
                        $ip     = $1;
                        $family = AF_INET();
                    } else {
                        $family = AF_INET6();
                    }
                } else {
                    croak 'Mandatory first argument must be a '
                        . 'defined IPv4/IPv6 address';
                }
            } else {
                croak 'Mandatory first argument must be a valid IPv4 address';
            }
        }
    } else {
        croak 'Mandatory first argument must be a defined IP address';
    }

    pdebug( "entering w/($oip)(@networks)", PDLEVEL1 );
    pIn();

    # Filter out non-IP data from @networks
    @networks = grep {
        if ( defined $_
            && m#^([\d\.]+|[abcdef\d:]+)(?:/(?:\d+|@{[ IP4REGEX ]}))?$#smio )
        {
            defined(
                $family == AF_INET()
                ? inet_aton($1)
                : inet_pton( AF_INET6(), $1 ) );
        }
    } @networks;

    # Start the comparisons
    if (@networks) {

        pdebug( "networks to compare: @{[ join ', ', @networks ]}",
            PDLEVEL2 );

        # Convert IP to binary
        $bip =
            $family == AF_INET()
            ? [ unpack 'N', inet_aton($ip) ]
            : [ unpack 'NNNN', inet_pton( AF_INET6(), $ip ) ];

        # Compare against all networks
        foreach (@networks) {

            if ( $_ =~ m#^([^/]+)(?:/(.+))?$#sm ) {
                ( $bnet, $bmask ) = ( $1, $2 );
            }

            # See if it's a network address
            if ( defined $bmask and length $bmask ) {

                # Get the netmask
                if ( $family == AF_INET() ) {

                    # Convert IPv4/CIDR notation to a binary number
                    $bmask =
                          ( $bmask =~ m/^\d+$/sm and $bmask <= MAXIPV4CIDR )
                        ? [ MASK - ( ( 2**( CHUNK - $bmask ) ) - 1 ) ]
                        : ( $bmask =~ m/^@{[ IP4REGEX ]}$/smo
                            and defined inet_aton($ip) )
                        ? [ unpack 'N', inet_aton($bmask) ]
                        : undef;

                } else {

                    # Convert IPv6 CIDR notation to a binary number
                    if ( $bmask =~ m/^\d+$/sm and $bmask <= MAXIPV6CIDR ) {

                        # Add the mask in 32-bit chunks
                        @tmp = ();
                        while ( $bmask >= CHUNK ) {
                            push @tmp, MASK;
                            $bmask -= CHUNK;
                        }

                        # Push the final segment if there's a remainder
                        if ($bmask) {
                            push @tmp,
                                MASK - ( ( 2**( CHUNK - $bmask ) ) - 1 );
                        }

                        # Add zero'd chunks to fill it out
                        while ( @tmp < IPV6CHUNKS ) {
                            push @tmp, 0x0;
                        }

                        # Finally, save the chunks
                        $bmask = [@tmp];

                    } else {
                        $bmask = undef;
                    }
                }

                # Skip if the netmask was invalid
                next unless defined $bmask;

                # Convert network address to binary
                $bnet =
                    $family == AF_INET()
                    ? [ unpack 'N', inet_aton($bnet) ]
                    : [ unpack 'NNNN', inet_pton( AF_INET6(), $bnet ) ];

                # Start comparing our chunks
                $irv = 1;
                @tmp = @$bip;
                while (@tmp) {
                    unless ( ( $tmp[0] & $$bmask[0] ) ==
                        ( $$bnet[0] & $$bmask[0] ) ) {
                        $irv = 0;
                        last;
                    }
                    shift @tmp;
                    shift @$bnet;
                    shift @$bmask;
                }
                if ($irv) {
                    pdebug( "matched against $_", PDLEVEL2 );
                    $rv = 1;
                    last;
                }

            } else {

                # Not a network address, so let's see if it's an exact match
                $bnet =
                    $family == AF_INET()
                    ? [ unpack 'N', inet_aton($_) ]
                    : [ unpack 'NNNN', inet_pton( AF_INET6(), $_ ) ];

                # Do the comparison
                $irv = 1;
                @tmp = @$bip;
                while (@tmp) {
                    unless ( $tmp[0] == $$bnet[0] ) {
                        $irv = 0;
                        last;
                    }
                    shift @tmp;
                    shift @$bnet;
                }
                if ($irv) {
                    pdebug( "matched against $_", PDLEVEL2 );
                    $rv = 1;
                    last;
                }
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
        @ips = ( $string =~ /(@{[ IP4REGEX ]})/smog );

        # Validate them by filtering through inet_aton
        foreach $ip (@ips) {
            push @rv, $ip if defined inet_aton($ip);
        }

        # If Socket6 is present or we have Perl 5.14 or higher we'll check
        # for IPv6 addresses
        if ( has_ipv6() or $] >= 5.012 ) {

            @ips = ( $string =~ m/(@{[ IP6REGEX ]})/smogix );

            # Filter out addresses with more than one ::
            @ips = grep { scalar(m/(::)/smg) <= 1 } @ips;

            # Validate remaining addresses with inet_pton
            foreach $ip (@ips) {
                push @rv, $ip
                    if defined inet_pton( AF_INET6(), $ip );
            }
        }
    }

    # Filter out IPv4 encoded as IPv6
    @rv = grep !/^::ffff:@{[ IP4REGEX ]}$/smo, @rv;

    pOut();
    pdebug( "leaving w/rv: @rv)", PDLEVEL1 );

    return @rv;
}

1;

__END__

=head1 NAME

Paranoid::Network - Network functions for paranoid programs

=head1 VERSION

$Id: Network.pm,v 0.67 2011/12/20 03:00:42 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Network;

  $rv = ipInNetwork($ip, @networks);
  $rv = hostInDomain($host, @domains);

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

=head1 DEPENDENCIES

=over

=item o

L<Paranoid>

=item o

L<Paranoid::Network::Socket>

=back

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

