# Paranoid::Module -- Paranoid Module Loading Routines
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Module.pm,v 0.81 2009/03/05 00:09:34 acorliss Exp $
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

package Paranoid::Module;

use 5.006;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS);
use base qw(Exporter);
use Paranoid;
use Paranoid::Debug qw(:all);
use Paranoid::Input;
use Carp;

($VERSION) = ( q$Revision: 0.81 $ =~ /(\d+(?:\.(\d+))+)/sm );

@EXPORT      = qw(loadModule);
@EXPORT_OK   = qw(loadModule);
%EXPORT_TAGS = ( all => [qw(loadModule)], );

#####################################################################
#
# Module code follows
#
#####################################################################

{
    my %tested;    # Hash of module names => boolean (load success)

    sub loadModule ($;@) {

        # Purpose:  Attempts to load a module via an eval.  Caches the
        #           result
        # Returns:  True (1) if the module was successfully loaded,
        #           False (0) if there are any errors
        # Usage:    $rv = loadModule($moduleName);

        my $module = shift;
        my @args   = @_;
        my $rv     = 0;
        my $a      = @args ? join ' ', @args : '';
        my $caller = scalar caller;
        my $c      = defined $caller ? $caller : 'undef';
        my $m;

        croak 'Mandatory first argument must be a defined module name'
            unless defined $module;

        pdebug( "entering w/($module)($a)", PDLEVEL1 );
        pIn();

        # Debug info
        pdebug( "calling package: $c", PDLEVEL2 );

        # Detaint module name
        if ( detaint( $module, 'filename', \$m ) ) {
            $module = $m;
        } else {
            Paranoid::ERROR =
                pdebug( 'failed to detaint module name' . " ($module)",
                PDLEVEL1 );
            $tested{$module} = 0;
        }

        # Skip if we've already done this
        unless ( exists $tested{$module} ) {

            # Try to load it
            $tested{$module} = eval "require $module; 1;" ? 1 : 0;

        }

        # Try to import symbol sets if requested
        if ( $tested{$module} && defined $caller ) {

            if (@args) {

                # Import requested symbol (sets)
                eval << "EOF";
{
  package $caller;
  import $module qw(@{[ join(' ', @args) ]});
  1;
}
EOF

            } else {

                # Import default symbols if no args passed
                eval << "EOF";
{
  package $caller;
  import $module;
  1;
}
EOF
            }
        }

        pOut();
        pdebug( "leaving w/rv: $tested{$module}", PDLEVEL1 );

        # Return result
        return $tested{$module};
    }
}

1;

__END__

=head1 NAME

Paranoid::Module -- Paranoid Module Loading Routines

=head1 VERSION

$Id: Module.pm,v 0.81 2009/03/05 00:09:34 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Module;

  $rv = loadModule($module, qw(:all));

=head1 DESCRIPTION

This provides a single function that allows you to do dynamic loading of
modules at runtime.

=head1 SUBROUTINES/METHODS

=head2 loadModule

  $rv = loadModule($module, qw(:all));

Accepts a module name and an optional list of arguments to 
use with the import function.  Returns a true or false depending
whether the require was successful.  We do not currently
track the return value of the import function.

=head1 DEPENDENCIES

=over

=item o

L<Paranoid>

=item o

L<Paranoid::Debug>

=back

=head1 BUGS AND LIMITATIONS

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

