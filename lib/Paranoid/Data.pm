# Paranoid::Data -- Misc. Data Manipulation Functions
#
# (c) 2007, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Data.pm,v 0.02 2010/04/15 23:23:28 acorliss Exp $
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

package Paranoid::Data;

use 5.006;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS);
use base qw(Exporter);
use Paranoid::Debug qw(:all);
use Carp;

($VERSION) = ( q$Revision: 0.02 $ =~ /(\d+(?:\.(\d+))+)/sm );

@EXPORT      = qw(deepCopy);
@EXPORT_OK   = qw(deepCopy);
%EXPORT_TAGS = ( all => [qw(deepCopy)], );

#####################################################################
#
# Module code follows
#
#####################################################################

sub deepCopy ($$) {

    # Purpose:  Attempts to safely copy an arbitrarily deep data
    #           structure from the source to the target
    # Returns:  True or False
    # Usage:    $rv = deepCopy($sourceRef, $targetRef);

    my $source  = shift;
    my $target  = shift;
    my $rv      = 1;
    my $counter = 0;
    my $sref    = defined $source ? ref $source : 'undef';
    my $tref    = defined $target ? ref $target : 'undef';
    my ( @refs, $recurseSub );

    croak 'Mandatory first argument must be a scalar, array, or hash '
        . 'reference'
        unless defined $source
            and ( $sref eq 'SCALAR' or $sref eq 'ARRAY' or $sref eq 'HASH' );
    croak 'Mandatory second argument must be a scalar, array, or hash '
        . 'reference'
        unless defined $target
            and ( $tref eq 'SCALAR' or $tref eq 'ARRAY' or $tref eq 'HASH' );
    croak 'First and second arguments must be identical types of '
        . 'references'
        unless $sref eq $tref;

    pdebug( "entering w/($sref)($tref)", PDLEVEL1 );
    pIn();

    $recurseSub = sub {
        my $s    = shift;
        my $t    = shift;
        my $type = ref $s;
        my $irv  = 1;
        my ( $key, $value );

        # We'll grep the @refs list to make sure there's no
        # circular references going on
        if ( grep { $_ eq $s } @refs ) {
            Paranoid::ERROR = pdebug(
                'Found a circular reference in data structure: '
                    . "@refs ($s)",
                PDLEVEL1
                );
            return 0;
        }

        # Push the reference onto the list
        push @refs, $s;

        # Copy data over
        if ( $type eq 'ARRAY' ) {

            # Copy over array elements
            foreach my $element (@$s) {

                $type = ref $element;
                $counter++;
                if ( $type eq 'ARRAY' or $type eq 'HASH' ) {

                    # Copy over sub arrays or hashes
                    push @$t, $type eq 'ARRAY' ? [] : {};
                    return 0 unless &$recurseSub( $element, $$t[-1] );

                } else {

                    # Copy over everything else as-is
                    push @$t, $element;
                }
            }

        } elsif ( $type eq 'HASH' ) {
            while ( ( $key, $value ) = each %$s ) {
                $type = ref $value;
                $counter++;
                if ( $type eq 'ARRAY' or $type eq 'HASH' ) {

                    # Copy over sub arrays or hashes
                    $$t{$key} = $type eq 'ARRAY' ? [] : {};
                    return 0 unless &$recurseSub( $value, $$t{$key} );

                } else {

                    # Copy over everything else as-is
                    $$t{$key} = $value;
                }
            }
        }

        # We're done, so let's remove the reference we were working on
        pop @refs;

        return 1;
    };

    # Start the copy
    if ( $sref eq 'ARRAY' or $sref eq 'HASH' ) {

        # Copy over arrays & hashes
        if ( $sref eq 'ARRAY' ) {
            @$target = ();
        } else {
            %$target = ();
        }
        $rv = &$recurseSub( $source, $target );

    } else {

        # Copy over everything else directly
        $$target = $$source;
        $counter++;
    }

    $rv = $counter if $rv;

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

1;

__END__

=head1 NAME

Paranoid::Data - Misc. Data Manipulation Functions

=head1 VERSION

$Id: Data.pm,v 0.02 2010/04/15 23:23:28 acorliss Exp $

=head1 SYNOPSIS

    $rv = deepCopy($sourceRef, $targetRef);

=head1 DESCRIPTION

This module provides data manipulation functions, which at this time only
consists of B<deepCopy>.

=head1 SUBROUTINES/METHODS

=head2 deepCopy

    $rv = deepCopy($sourceRef, $targetRef);

This function performs a deep and safe copy of arbitrary data structures,
checking for circular references along the way.  Hashes and lists are safely
duplicated while all other data types are just copied.  This means that any
embedded object references, etc., are identical in both the source and the
target, which is probably not what you want.

In short, this should only be used on pure hash/list/scalar value data
structures.  Both the source and the target reference must be of an identical
type.

This function returns the number of elements copied unless it runs into a
problem (such as a circular reference), in which case it returns a zero.

=head1 DEPENDENCIES

=over

=item o

L<Paranoid::Debug>

=back

=head1 BUGS AND LIMITATIONS 

=head1 AUTHOR 

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2009, Arthur Corliss (corliss@digitalmages.com)

