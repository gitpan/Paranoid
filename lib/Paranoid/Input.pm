# Paranoid::Input -- Paranoid input functions
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Input.pm,v 0.14 2009/03/04 09:32:51 acorliss Exp $
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

package Paranoid::Input;

use 5.006;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS);
use base qw(Exporter);
use Fcntl qw(:flock);
use Paranoid;
use Paranoid::Debug qw(:all);
use Carp;

($VERSION) = ( q$Revision: 0.14 $ =~ /(\d+(?:\.(\d+))+)/sm );

@EXPORT    = qw(FSZLIMIT       slurp     detaint     stringMatch);
@EXPORT_OK = qw(FSZLIMIT       slurp     detaint     stringMatch
    addTaintRegex);
%EXPORT_TAGS = (
    all => [
        qw(FSZLIMIT       slurp     detaint     stringMatch
            addTaintRegex)
           ],
);

#####################################################################
#
# Module code follows
#
#####################################################################

{

    my $fszlimit = 16 * 1024;

    sub FSZLIMIT : lvalue {

        # Purpose:  Gets/sets $fszlimit
        # Returns:  $fszlimit
        # Usage:    $limit = FSZLIMIT;
        # Usage:    FSZLIMIT = 100;

        $fszlimit;
    }

}

sub slurp ($$;$) {

    # Purpose:  Reads a file into memory provided it doesn't exceed FSZLIMIT
    #           in size.  Automatically splits it into lines, but optionally
    #           chomps them as well.
    # Returns:  True (1) if the file was successfully read,
    #           False (0) if there are any errors
    # Usage:    $rv = slurp($filename, \@lines);
    # Usage:    $rv = slurp($filename, \@lines, 1);

    my $file    = shift;
    my $aref    = shift;
    my $doChomp = shift || 0;
    my $rv      = 0;
    my ( $fd, $b, $line, @lines );

    # Validate arguments
    croak 'Mandatory first argument must be a defined filename'
        unless defined $file;
    croak 'Mandatory second argument must be an array reference'
        unless defined $aref && ref $aref eq 'ARRAY';

    pdebug( "entering w/($file)($aref)($doChomp)", PDLEVEL1 );
    pIn();
    @$aref = ();

    # Validate file and exit early, if need be
    unless ( -e $file && -r _ ) {
        if ( !-e _ ) {
            Paranoid::ERROR =
                pdebug( "file ($file) does not exist", PDLEVEL1 );
        } else {
            Paranoid::ERROR =
                pdebug( "file ($file) is not readable by the effective user",
                PDLEVEL1 );
        }
        pOut();
        pdebug( "leaving w/rv: $rv", PDLEVEL1 );
        return 0;
    }
    unless ( detaint( $file, 'filename', \$b ) ) {
        Paranoid::ERROR =
            pdebug( "failed to detaint filename: $file", PDLEVEL1 );
        pOut();
        pdebug( "leaving w/rv: $rv", PDLEVEL1 );
        return 0;
    }

    # Read the file
    @$aref = ();
    if ( open $fd, '<', $file ) {
        flock $fd, LOCK_SH;
        $b = read $fd, $line, FSZLIMIT() + 1;
        flock $fd, LOCK_UN;
        close $fd;

        # Process what was read
        if ( defined $b ) {
            if ( $b > 0 ) {
                if ( $b > FSZLIMIT ) {
                    Paranoid::ERROR = pdebug(
                        "file '$file' is larger than " . FSZLIMIT . ' bytes',
                        PDLEVEL1
                    );
                } else {
                    $rv = 1;
                }
                while ( length $line > 0 ) {
                    $line       =~ /\n/sm
                        ? $line =~ s/^(.*?\n)//sm
                        : $line =~ s/(.*)//sm;
                    push @lines, $1;
                }
            }
        } else {
            Paranoid::ERROR =
                pdebug( "error reading file ($file): $!", PDLEVEL1 );
        }
        pdebug( "read @{[ scalar @lines ]} lines.", PDLEVEL1 );

        # Chomp lines
        do {
            foreach (@lines) {s/\r?\n$//sm}
        } if $doChomp;

        # Populate $aref with results
        @$aref = @lines;

    } else {
        Paranoid::ERROR =
            pdebug( "error opening file ($file): $!", PDLEVEL1 );
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

{
    my %regexes = (
        alphabetic   => qr/[a-zA-Z]+/sm,
        alphanumeric => qr/[a-zA-Z0-9]+/sm,
        alphawhite   => qr/[a-zA-Z\s]+/sm,
        alnumwhite   => qr/[a-zA-Z0-9\s]+/sm,
        email =>
            qr/[a-zA-Z][\w\.\-]*\@(?:[a-zA-Z0-9][a-zA-Z0-9\-]*\.)*[a-zA-Z0-9]+/sm,
        filename => qr#[/ \w\-\.:,@\+]+\[?#sm,
        fileglob => qr#[/ \w\-\.:,@\+\*\?\{\}\[\]]+\[?#sm,
        hostname => qr/(?:[a-zA-Z0-9][a-zA-Z0-9\-]*\.)*[a-zA-Z0-9]+/sm,
        ipaddr   => qr/(?:\d+\.){3}\d+/sm,
        netaddr  => qr#^(?:\d+\.){3}\d+(?:/(?:\d+|(?:\d+\.){3}\d+))?$#sm,
        login    => qr/[a-zA-Z][\w\.\-]*/sm,
        nometa   => qr/[^\%\`\$\!\@]+/sm,
        number   => qr/[+\-]?[0-9]+(?:\.[0-9]+)?/sm,
    );

    sub addTaintRegex ($$) {

        # Purpose:  Adds another regular expression to the internal hash
        # Returns:  True (1) if passed string is defined, False (0) if undef
        # Usage:    $rv = addTaintRegex($name, $regex);

        my $name  = shift;
        my $regex = shift;

        # TODO: Needs to enclose in an eval in case of bad regexes being
        # TODO: passed

        $regexes{$name} = qr/$regex/sm if defined $regex;

        return defined $regex ? 1 : 0;
    }

    sub _getTaintRegex ($) {

        # Purpose:  Retrieves the named regex
        # Returns:  Regex if named regex is defined, undef otherwise
        # Usage:    $regex = _getTaintRegex($name);

        my $name = shift;
        return ( defined $name && exists $regexes{$name} )
            ? $regexes{$name}
            : undef;
    }
}

sub detaint ($$$) {

    # Purpose:  Detaints and validates input in one call
    # Returns:  True (1) if detainting was successful,
    #           False (0) if there are any errors
    # Usage:    $rv = detaint($input, $dataType, \$detainted);

    my $input = shift;
    my $type  = shift;
    my $sref  = shift;
    my $rv    = 0;
    my $regex = _getTaintRegex($type);
    my $istr  = defined $input ? $input : 'undef';
    my $dstr  = defined $type ? $type : 'undef';

    # Validate arguments
    croak 'Mandatory third argument must be a valid scalar reference'
        unless defined $sref && ref $sref eq 'SCALAR';

    pdebug( "entering w/($istr)($dstr)($sref)", PDLEVEL1 );
    pIn();

    # Zero out contents of $sref
    $$sref = undef;

    # Is everything kosher for processing?
    if ( defined $input and length $input and defined $regex ) {

        # It is, so detaint
        ($$sref) = ( $input =~ /^($regex)$/sm );

        # Report the results
        if ( defined $$sref && length $$sref > 0 ) {
            $rv = 1;
            pdebug( "detainted value ($$sref)", PDLEVEL1 );
        } else {
            pdebug( 'failed to detaint input', PDLEVEL1 );
        }

    } else {

        # Bad arguments -- report and return false
        Paranoid::ERROR =
            pdebug( "bad arguments passed ($istr)($dstr)", PDLEVEL1 );
        $rv = 0;
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub stringMatch ($@) {

    # Purpose:  Looks for occurrences of strings and/or regexes in the passed
    #           input
    # Returns:  True (1) any of the strings/regexes match,
    #           False (0), otherwise
    # Usage:    $rv = stringMatch($input, @words);

    my $input = shift;
    my @match = @_;
    my $rv    = 0;
    my ( @regex, $r );

    # Validate arguments
    croak 'Mandatory first argument must be defined input'
        unless defined $input;
    croak 'Mandatory string matches must be passed after input'
        unless @match;

    pdebug( "entering w/($input)(@match)", PDLEVEL1 );
    pIn();

    # Populate @regex w/regexes
    @regex = grep { defined $_ && ref $_ eq 'Regexp' } @match;

    # Convert remaining strings to regexes
    foreach ( grep { defined $_ && ref $_ ne 'Regexp' } @match ) {
        push @regex, m#^/(.+)/$#sm ? qr#$1#smi : qr#\Q$_\E#smi;
    }

    # Start comparisons
    study $input;
    foreach $r (@regex) {
        if ( $input =~ /$r/smi ) {
            $rv = 1;
            last;
        }
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

1;

__END__

=head1 NAME

Paranoid::Input - Paranoid input function

=head1 VERSION

$Id: Input.pm,v 0.14 2009/03/04 09:32:51 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Input;

  FSZLIMIT = 64 * 1024;

  $rv = slurp($filename, \@lines);
  addTaintRegex("telephone", qr/\(\d{3}\)\s+\d{3}-\d{4}/);
  $rv = detaint($userInput, "login", \$val);
  $rv = stringMatch($input, @strings);

=head1 DESCRIPTION

The modules provide safer routines to use for input activities such as reading
files and detainting user input.

B<addTaintRegex> is only exported if this module is used with the B<:all> target.

=head1 SUBROUTINES/METHODS

=head2 FSZLIMIT

The value returned/set by this lvalue function is the maximum file size that
will be read into memory.  This affects functions like B<slurp> (documented
below).

=head2 slurp

  $rv = slurp($filename, \@lines);

This function allows you to read a file in its entirety into memory, the lines
of which are placed into the passed array reference.  This function will only
read files up to B<FSZLIMIT> in size.  Flocking is used (with B<LOCK_SH>) and 
the read is a blocking read.

An optional third argument sets a boolean flag which, if true, determines if
all lines are automatically chomped.  If chomping is enabled this will strip
both UNIX and DOS line separators.

The return value is false if the read was unsuccessful or the file's size
exceeded B<FSZLIMIT>.  In the latter case the array reference will still be
populated with what was read.  The reason for the failure can be retrieved
B<from Paranoid::ERROR>.

=head2 addTaintRegex

  addTaintRegex("telephone", qr/\(\d{3}\)\s+\d{3}-\d{4}/);

This adds a regular expression which can used by name to detaint user input
via the B<detaint> function.  This will allow you to overwrite the internally
provided regexes or as well as your own.

=head2 detaint

  $rv = detaint($userInput, "login", \$val);

This function populates the passed reference with the detainted input from the
first argument.  The second argument specifies the type of data in the first
argument, and is used to validate the input before detainting.  The following
data types are currently known:

  alphabetic            ^([a-zA-Z]+)$
  alphanumeric          ^([a-zA-Z0-9])$
  email                 ^([a-zA-Z][\w\.\-]*\@
                        (?:[a-zA-Z0-9][a-zA-Z0-9\-]*\.)*
                        [a-zA-Z0-9]+)$
  filename              ^[/ \w\-\.:,@\+]+\[?$
  fileglob              ^[/ \w\-\.:,@\+\*\?\{\}\[\]]+\[?$
  hostname              ^(?:[a-zA-Z0-9][a-zA-Z0-9\-]*\.)*
                        [a-zA-Z0-9]+)$
  ipaddr                ^(?:\d+\.){3}\d+$
  netaddr               ^(?:\d+\.){3}\d+(?:/(?:\d+|
                        (?:\d+\.){3}\d+))?$
  login                 ^([a-zA-Z][\w\.\-]*)$
  nometa                ^([^\`\$\!\@]+)$
  number                ^([+\-]?[0-9]+(?:\.[0-9]+)?)$

If the first argument fails to match against these regular expressions the
function will return 0.  If the string passed is either undefined or a
zero-length string it will also return 0.  And finally, if you attempt to use
an unknown (or unregistered) data type it will also return 0, and log an error
message in B<Paranoid::ERROR>.

B<NOTE>:  This is a small alteration in previous behavior.  In previous
versions if an undef or zero-length string was passed, or if the data type was
unknown the code would croak.  That was, perhaps, a tad overzealous on my
part.

=head2 stringMatch

  $rv = stringMatch($input, @strings);

This function does a multiline case insensitive regex match against the 
input for every string passed for matching.  This does safe quoted matches 
(\Q$string\E) for all the strings, unless the string is a perl Regexp 
(defined with qr//) or begins and ends with /.

B<NOTE>: this performs a study in hopes that for a large number of regexes
will be performed faster.  This may not always be the case.

=head1 DEPENDENCIES

=over

=item o

L<Fcntl>

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

