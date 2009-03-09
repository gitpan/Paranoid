# Paranoid::Debug -- Debug support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Debug.pm,v 0.91 2009/03/05 00:08:07 acorliss Exp $
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

package Paranoid::Debug;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS);
use base qw(Exporter);
use Paranoid;

use constant PDLEVEL1 => 9;
use constant PDLEVEL2 => 10;
use constant PDLEVEL3 => 11;
use constant PDLEVEL4 => 12;

($VERSION) = ( q$Revision: 0.91 $ =~ /(\d+(?:\.(\d+))+)/sm );

@EXPORT    = qw(PDEBUG pdebug perror pIn pOut psetDebug PDPREFIX);
@EXPORT_OK = qw(PDEBUG pdebug perror pIn pOut psetDebug PDPREFIX
    PDLEVEL1 PDLEVEL2 PDLEVEL3 PDLEVEL4);
%EXPORT_TAGS = (
    all => [
        qw(PDEBUG pdebug perror pIn pOut psetDebug PDPREFIX
            PDLEVEL1 PDLEVEL2 PDLEVEL3 PDLEVEL4)
           ],
);

#####################################################################
#
# Module code follows
#
#####################################################################

{
    my $ilevel = 0;    # Start with no identation
    my $pdebug = 0;    # Start with debug output disabled

    my $defprefix = sub {

        # Default Prefix to use with debug messages looks like:
        #
        #   [PID - ILEVEL] Subroutine:
        #
        my $caller = ( caller 2 )[3];
        my $prefix;

        $caller = defined $caller ? $caller : 'undef';
        $prefix = ' ' x $ilevel . "[$$-$ilevel] $caller: ";

        return $prefix;
    };
    my $pdprefix = $defprefix;

    sub PDEBUG : lvalue {
        $pdebug;
    }

    sub ILEVEL : lvalue {
        $ilevel;
    }

    sub PDPREFIX : lvalue {
        $pdprefix;
    }
}

sub perror ($) {

    # Purpose:  Print passed string to STDERR
    # Returns:  Return value from print function
    # Usage:    $rv = perror("Foo!");

    my $msg = shift;

    return print STDERR "$msg\n";
}

sub pdebug ($;$) {

    # Purpose:  Calls perror() if the message level is less than or equal to
    #           the value of PDBEBUG, after prepending the string returned by
    #           the PDPREFIX routine, if defined
    # Returns:  Always returns the passed message, regardless of PDEBUG's
    #           value
    # Usage:    pdebug($message, $level);

    my $msg    = shift;
    my $level  = shift || 1;
    my $prefix = PDPREFIX;

    return $msg if $level > PDEBUG;

    # Execute the code block, if that's what it is
    $prefix = &$prefix() if ref($prefix) eq 'CODE';

    perror("$prefix$msg");

    return $msg;
}

sub pIn () {

    # Purpose:  Increases indentation level
    # Returns:  Always True (1)
    # Usage:    pIn();

    my $i = ILEVEL;
    ILEVEL = ++$i;

    return 1;
}

sub pOut () {

    # Purpose:  Decreases indentation level
    # Returns:  Always True (1)
    # Usage:    pOut();

    my $i = ILEVEL;
    ILEVEL = --$i if $i >= 0;

    return 1;
}

# TODO:  Kill this freaking thing (psetDebug)

sub psetDebug (@) {

    # Purpose:  Set PDEBUG equal to the number of 'v's in '-v...'
    # Returns:  PDEBUG (after counting v's)
    # Usage:    psetDebug(@ARGV);

    my @args = @_;
    my $v;

    # Extract all ^-v+$ arguments
    $v = join '', grep /^-v+$/sm, @args;
    $v =~ s/-//smg;

    # Set debug level
    PDEBUG = length $v;

    return PDEBUG;
}

1;

__END__

=head1 NAME

Paranoid::Debug - Trace message support for paranoid programs

=head1 VERSION

$Id: Debug.pm,v 0.91 2009/03/05 00:08:07 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Debug;

  PDEBUG = 1;
  PDPREFIX = sub { scalar localtime };
  pdebug("starting program", 1);
  foo();

  sub foo {
    pdebug("entering foo()", 2);
    pIn();

    pdebug("someting happened!", 2);

    pOut();
    pdebug("leaving w/rv: $rv", 2):
  }

  perror("error msg");

  psetDebug(@ARGV);

=head1 DESCRIPTION

The purpose of this module is to provide a barely useful framework to produce
debugging output.  With this module you can assign a level of detail to pdebug
statements, and they'll only be displayed when PDEBUG is set to that level or
higher.  This allows you to have your program produce varying levels of
debugging output.

Using the B<pIn> and B<pOut> functions at the beginning and end of each
function will cause debugging output to be indented appropriately so you can
visually see the level of recursion.

B<NOTE:> This module provides a function called B<perror> which conflicts with
a similar function provided by the B<POSIX> module.  If you use this module
you should avoid using or importing POSIX's version of this function.

B<NOTE:> All modules within the Paranoid framework use this module.  Their
debug levels range from 9 and up.  You should use 1 - 8 for your own modules
or code.

=head1 SUBROUTINES/METHODS

=head2 PDEBUG

B<PDEBUG> is an lvalue subroutine which is initially set to 0, but can be 
set to any positive integer.  The higher the number the higher the level 
of pdebug statements are printed.

=head2 PDPREFIX

B<PDPREFIX> is also an lvalue subroutien and is set by default to a 
subroutine that returns as a string the standard prefix for debug 
messages:

  [PID - ILEVEL] Subroutine:

Assigning another subroutine reference to a subroutine can override this 
behavior.

=head2 perror

  perror("error msg");

This function prints the passed message to STDERR.

=head2 pdebug

  pdebug("debug statement", 3);

This function is called with one mandatory argument (the string to be
printed), and an optional integer.  This integer is compared against B<PDEBUG>
and the debug statement is printed if PDEBUG is equal to it or higher.

The return value is always the debug statement itself.  This allows for a
single statement to produce debug output and set variables.  For instance:

  Paranoid::ERROR = pdebug("Something bad happened!", 3);

=head2 pIn

  pIn();

This function causes all subsequent pdebug messages to be indented by one
additional space.

=head2 pOut

  pOut();

This function causes all subsequent pdebug messages to be indented by one
less space.

=head2 psetDebug

  psetDebug(@ARGV);

This function extracts all ^-v+$ arguments from the passed list and counts the
number of 'v's that result, and sets B<PDEBUG> to that count.  You would
typically use this by passing @ARGV for command-line programs.

B<NOTE>:  This was a dumb idea of incredible proportions.  As soons as it is
safe to do so I will kill this function and perform my penance before the gods
of bitrot.  Consider this deprecated.

=head1 DEPENDENCIES

L<Paranoid>

=head1 BUGS AND LIMITATIONS

B<perror> (and by extension, B<pdebug>) will generate errors if STDERR is
closed elsewhere in the program.

There is also no upper limit on how much indentation will be used by the
program, so if you're using B<pIn> in deeply recursive call stacks you can
expect some overhead due some rather large strings being bandied about.

=head1 AUTHOR

(c) 2005 Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

