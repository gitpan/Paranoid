# Paranoid::Network::IPv6 -- IPv6-specific network functions
#
# (c) 2012, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: IPv6.pm,v 0.1 2012/05/29 21:37:44 acorliss Exp $
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

package Paranoid::Network::IPv6;

use 5.006;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS);
use base qw(Exporter);
use Paranoid::Debug qw(:all);
use Paranoid::Network::Socket;
use Carp;

($VERSION) = ( q$Revision: 0.1 $ =~ /(\d+(?:\.(\d+))+)/sm );
@EXPORT    = qw(ipv6NetConvert ipv6NetPacked ipv6NetIntersect);
@EXPORT_OK = (
    @EXPORT,
    qw(MAXIPV6CIDR IPV6REGEX IPV6CIDRRGX IPV6BASE IPV6BRDCST IPV6MASK)
    );
%EXPORT_TAGS = ( all => [@EXPORT_OK] );

use constant MAXIPV6CIDR => 64;
use constant IPV6REGEX   => qr/
                            :(?::[abcdef\d]{1,4}){1,7}                 | 
                            [abcdef\d]{1,4}(?:::?[abcdef\d]{1,4}){1,7} | 
                            (?:[abcdef\d]{1,4}:){1,7}: 
                            /smix;
use constant IPV6CIDRRGX => qr#(@{[ IPV6REGEX ]})(?:/(\d+))?#sm;
use constant IPV6BASE    => 0;
use constant IPV6BRDCST  => 1;
use constant IPV6MASK    => 2;
use constant CHUNKMASK   => 0xffffffff;
use constant CHUNK       => 32;
use constant IPV6CHUNKS  => 4;
use constant IPV6LENGTH  => 16;

#####################################################################
#
# Module code follows
#
#####################################################################

sub ipv6NetConvert ($) {

    # Purpose:  Takes a string representation of an IPv6 network
    #           address and returns a list of lists containing
    #           the binary network address, broadcast address,
    #           and netmask, each broken into 32bit chunks.
    #           Also allows for a plain IP being passed, in which
    #           case it only returns the binary IP.
    # Returns:  Array, empty on errors
    # Usage:    @network = ipv6NetConvert($netAddr);

    my $netAddr = shift;
    my $n = defined $netAddr ? $netAddr : 'undef';
    my ( $bnet, $bmask, @tmp, @rv );

    pdebug( "entering w/$n", PDLEVEL1 );
    pIn();

    if ( has_ipv6() or $] >= 5.012) {

        # Extract net address, mask
        if ( defined $netAddr ) {
            ( $bnet, $bmask ) = ( $netAddr =~ m#^@{[ IPV6CIDRRGX ]}$#sm );
        }

        if ( defined $bnet and length $bnet ) {

            # First, convert $bnet to see if we have a valid IP address
            $bnet = [ unpack 'NNNN', inet_pton( AF_INET6(), $bnet ) ];

            if ( defined $bnet and length $bnet ) {

                # Save our network address
                push @rv, $bnet;

                if ( defined $bmask and length $bmask ) {

                    # Convert netmask
                    if ( $bmask <= MAXIPV6CIDR ) {

                        # Add the mask in 32-bit chunks
                        @tmp = ();
                        while ( $bmask >= CHUNK ) {
                            push @tmp, CHUNKMASK;
                            $bmask -= CHUNK;
                        }

                        # Push the final segment if there's a remainder
                        if ($bmask) {
                            push @tmp,
                                CHUNKMASK - ( ( 2**( CHUNK - $bmask ) ) - 1 );
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

                    if ( defined $bmask ) {

                        # Apply the mask to the base address
                        foreach ( 0 .. (IPV6CHUNKS - 1)) {
                            $$bnet[$_] &= $$bmask[$_];
                        }

                        # Calculate and save our broadcast address
                        @tmp = ();
                        foreach ( 0 .. (IPV6CHUNKS - 1)) {
                            $tmp[$_] =
                                $$bnet[$_] | ( $$bmask[$_] ^ CHUNKMASK );
                        }
                        push @rv, [@tmp];

                        # Save our mask
                        push @rv, $bmask;

                    } else {
                        pdebug( 'invalid netmask passed', PDLEVEL1 );
                    }
                }

            } else {
                pdebug( 'failed to convert IPv6 address', PDLEVEL1 );
            }
        } else {
            pdebug( 'failed to extract an IPv6 address', PDLEVEL1 );
        }

    } else {
        pdebug( 'IPv6 support not present', PDLEVEL1 );
    }

    pOut();
    pdebug( "leaving w/rv: @rv", PDLEVEL1 );

    return @rv;
}

sub ipv6NetPacked ($) {

    # Purpose:  Wrapper script for ipv6NetConvert that repacks all of its
    #           32bit chunks into opaque strings in network-byte order.
    # Returns:  Array
    # Usage:    @network = ipv6NetPacked($netAddr);

    my $netAddr = shift;
    my $n = defined $netAddr ? $netAddr : 'undef';
    my @rv;

    pdebug( "entering w/$n", PDLEVEL1 );
    pIn();

    @rv = ipv6NetConvert($netAddr);
    foreach (@rv) {
        $_ = pack 'NNNN', @$_;
    }

    pOut();
    pdebug( "leaving w/@rv", PDLEVEL1 );

    return @rv;
}

sub _cmpArrays ($$) {

    # Purpose:  Compares IPv6 chunked address arrays
    # Returns:  -1:  net1 < net 2
    #            0:  net1 == net2
    #            1:  net1 > net2
    # Usage:    $rv = _cmpArrays( $aref1, $aref2 );

    my $aref1 = shift;
    my $aref2 = shift;
    my $rv    = 0;

    pdebug( "entering w/$aref1, $aref2", PDLEVEL2 );
    pIn();

    while ( scalar @$aref1 ) {
        unless ( $$aref1[0] == $$aref2[0] ) {
            $rv = $$aref1[0] > $$aref2[0] ? 1 : -1;
            last;
        }
        shift @$aref1;
        shift @$aref2;
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL2 );

    return $rv;
}

sub ipv6NetIntersect (@) {

    # Purpose:  Tests whether network address ranges intersect
    # Returns:  Integer, denoting whether an intersection exists, and what
    #           kind:
    #
    #              -1: destination range encompasses target range
    #               0: both ranges do not intersect at all
    #               1: target range encompasses destination range
    #
    # Usage:    $rv = ipv6NetIntersect($net1, $net2);

    my $tgt  = shift;
    my $dest = shift;
    my $t    = defined $tgt ? $tgt : 'undef';
    my $d    = defined $dest ? $dest : 'undef';
    my $rv   = 0;
    my ( @tnet, @dnet );

    pdebug( "entering w/$t, $d", PDLEVEL1 );
    pIn();

    # Bypas if one or both isn't defined -- obviously no intersection
    unless ( !defined $tgt or !defined $dest ) {

        # Treat any array references as IPv6 addresses already translated into
        # 32bit integer chunks
        @tnet = ref($tgt)  eq 'ARRAY' ? $tgt  : ipv6NetConvert($tgt);
        @dnet = ref($dest) eq 'ARRAY' ? $dest : ipv6NetConvert($dest);

        # insert bogus numbers for non IP-address info
        @tnet = ( [ -1, 0, 0, 0 ] ) unless scalar @tnet;
        @dnet = ( [ -2, 0, 0, 0 ] ) unless scalar @dnet;

        # Dummy up broadcast address for those single IPs passed (in lieu of
        # network ranges)
        if ( $#tnet == 0 ) {
            $tnet[IPV6BRDCST] = $tnet[IPV6BASE];
            $tnet[IPV6MASK] = [ CHUNKMASK, CHUNKMASK, CHUNKMASK, CHUNKMASK ];
        }
        if ( $#dnet == 0 ) {
            $dnet[IPV6BRDCST] = $dnet[IPV6BASE];
            $dnet[IPV6MASK] = [ CHUNKMASK, CHUNKMASK, CHUNKMASK, CHUNKMASK ];
        }

        if (    _cmpArrays( $tnet[IPV6BASE], $dnet[IPV6BASE] ) <= 0
            and _cmpArrays( $tnet[IPV6BRDCST], $dnet[IPV6BRDCST] ) >= 0 ) {

            # Target fully encapsulates dest
            $rv = 1;

        } elsif ( _cmpArrays( $tnet[IPV6BASE], $dnet[IPV6BASE] ) >= 0
            and _cmpArrays( $tnet[IPV6BRDCST], $dnet[IPV6BRDCST] ) <= 0 ) {

            # Dest fully encapsulates target
            $rv = -1;

        }
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

1;

__END__

=head1 NAME

Paranoid::Network::IPv6 - IPv6-related functions

=head1 VERSION

$Id: IPv6.pm,v 0.1 2012/05/29 21:37:44 acorliss Exp $

=head1 SYNOPSIS

=head1 DESCRIPTION

This module contains a few convenience functions for working with IPv6
addresses.

By default only the subroutines themselves are imported.  Requesting B<:all>
will also import the constants as well.

=head1 SUBROUTINES/METHODS

=head2 ipv6NetConvert

    @net = ipv6NetConvert($netAddr);

This function takes an IPv4 network address in string format and converts it 
into and array of arrays.  The arrays will contain the base network address, 
the broadcast address, and the netmask, each split into native 32bit integer 
format chunks.  Each sub array is essentially what you would get from:

    @chunks = unpack 'NNNN', inet_pton(AF_INET6, '::1');

using '::1' as the sample IPv6 address.

The network address must have the netmask in CIDR format.  In the case of a 
single IP address, the array with only have one subarray, that of the IP 
itself, split into 32bit integers.

Passing any argument to this function that is not a string representation of
an IP address (including undef values) will cause this function to return an
empty array.

=head2 ipv6NetPacked

    @net = ipv6NetPacked('fe80::/64');

This function is a wrapper for B<ipv6NetConvert>, but instead of subarrays
each element is the packed (opaque) string as returned by B<inet_pton>.

=head2 ipv6NetIntersect

    $rv = ipv6NetIntersect($net1, $net2);

This function tests whether an IP or subnet intersects with another IP or
subnet.  The return value is essentially boolean, but the true value can vary
to indicate which is a subset of the other:

    -1: destination range encompasses target range
     0: both ranges do not intersect at all
     1: target range encompasses destination range

The function handles the same string formats as B<ipv6NetConvert>, but will
allow you to test single IPs in integer format as well.

=head1 CONSTANTS

These are only imported if explicity requested or with the B<:all> tag.

=head2 MAXIPV6CIDR

Simply put: 64.  This is the largest CIDR notation supported in IPv6.

=head2 IPV6REGEX

Regular expression: 

                            qr/
                            :(?::[abcdef\d]{1,4}){1,7}                 | 
                            [abcdef\d]{1,4}(?:::?[abcdef\d]{1,4}){1,7} | 
                            (?:[abcdef\d]{1,4}:){1,7}: 
                            /smix;

You can use this for validating IP addresses as such:

    $ip =~ m#^@{[ IPV6REGEX ]}$#;

or to extract potential IPs from  extraneous text:

    (@ips) = ( $string =~ m#(@{[ IPV6REGEX ]})#g);

=head2 IPV6CIDRRGX

Regular expression: 

    qr#(@{[ IPV6REGEX ]})(?:/(\d+))?#sm

By default this will extract an IP or CIDR notation network address:

    ($net, $mask) = ( $ip =~ m#^@{[ IPV6CIDRRGX ]}$# );

In the case of a simple IP address B<$mask> will be undefined.

=head2 IPV6BASE

This is the ordinal index of the base network address as returned by
B<ipv6NetConvert>.

=head2 IPV6BRDCST

This is the ordinal index of the broadcast address as returned by 
B<ipv6NetConvert>.

=head2 IPV6MASK

This is the ordinal index of the network mask as returned by 
B<ipv6NetConvert>.

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

(c) 2012, Arthur Corliss (corliss@digitalmages.com)

