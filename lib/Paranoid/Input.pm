# Paranoid::Input -- Paranoid input functions
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Input.pm,v 0.10 2008/02/27 06:48:51 acorliss Exp $
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

Paranoid::Input - Paranoid input function

=head1 MODULE VERSION

$Id: Input.pm,v 0.10 2008/02/27 06:48:51 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Input;

  FSZLIMIT = 64 * 1024;

  $rv = slurp($filename, \@lines);
  addTaintRegex("telephone", qr/\(\d{3}\)\s+\d{3}-\d{4}/);
  $rv = detaint($userInput, "login", \$val);

=head1 REQUIREMENTS

Fcntl
Paranoid
Paranoid::Debug

=head1 DESCRIPTION

The modules provide safer routines to use for input activities such as reading
files and detainting user input.

B<addTaintRegex> is only exported if this module is used with the B<:all> target.

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::Input;

use strict;
use warnings;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use Exporter;
use Fcntl qw(:flock);
use Paranoid;
use Paranoid::Debug;
use Carp;

($VERSION)    = (q$Revision: 0.10 $ =~ /(\d+(?:\.(\d+))+)/);

@ISA          = qw(Exporter);
@EXPORT       = qw(FSZLIMIT slurp detaint stringMatch);
@EXPORT_OK    = qw(FSZLIMIT slurp detaint addTaintRegex stringMatch);
%EXPORT_TAGS  = (
  all => [qw(FSZLIMIT slurp detaint addTaintRegex stringMatch)],
  );

#####################################################################
#
# Module code follows
#
#####################################################################

=head1 VARIABLES

=head2 FSZLIMIT

Setting this variable defines how large a block your reads will be in bytes.
By default it is set to 16KB.

=cut

{

  my $FSZLIMIT  = 16 * 1024;
  
  sub FSZLIMIT : lvalue {
    $FSZLIMIT;
  }

}

=head1 FUNCTIONS

=head2 slurp

  $rv = slurp($filename, \@lines);

This function allows you to read a file in its entirety into memory, the lines
of which are placed into the passed array reference.  This function will only
read files up to B<FSZLIMIT> in size.  Flocking is used (with B<LOCK_SH>) and 
the read is a blocking read.

An optional third argument sets a boolean flag which, if true, determines if
all lines are automatically chomped.  If chomping is enabled this will strip
both UNIX and DOS line separators.

The return value is fales if the read was unsuccessful or the file's size
exceeded B<FSZLIMIT>.  In the latter case the array reference will still be
populated with what was read.  The reason for the failure can be retrieved
B<from Paranoid::ERROR>.

=cut

sub slurp ($$;$) {
  my $file    = shift;
  my $aref    = shift;
  my $doChomp = shift || 0;
  my $rv      = 0;
  my ($fd, $b, $line, @lines);

  # Validate args
  croak "No file argument was passed to slurp()"
    unless defined $file;
  croak "No array reference was passed to slurp()"
    unless defined $aref && ref($aref) eq 'ARRAY';

  pdebug("entering w/($file)($aref)($doChomp)", 9);
  pIn();
  @$aref = ();

  # Validate file and exit early, if need be
  unless (-e $file && -r _) {
    if (! -e _) {
      Paranoid::ERROR = pdebug("file ($file) does not exist", 9);
    } else {
      Paranoid::ERROR = pdebug(
        "file ($file) is not readable by the effective user", 9);
    }
    pOut();
    pdebug("leaving w/rv: $rv", 9);
    return $rv;
  }

  # Read the file
  @$aref = ();
  if (open($fd, "< $file")) {
    flock $fd, LOCK_SH;
    $b = read $fd, $line, FSZLIMIT() + 1;
    flock $fd, LOCK_UN;
    close($fd);

    # Process what was read
    if (defined $b) {
      if ($b > 0) {
        if ($b > FSZLIMIT) {
          Paranoid::ERROR = pdebug("file '$file' is larger than " .  
            FSZLIMIT() . " bytes", 9);
        } else {
          $rv = 1;
        }
        while (length($line) > 0) {
          $line =~ /\n/m ? $line =~ s/^(.*?\n)//m : $line =~ s/(.*)//m;
          push(@lines, $1);
        }
      }
    } else {
      Paranoid::ERROR = pdebug("error reading file ($file): $!", 9);
    }
    pdebug("read @{[ scalar @lines ]} lines.", 9);

    # Chomp lines
    do {
      foreach (@lines) { s/\r?\n$//m };
    } if $doChomp;

    # Populate $aref with results
    @$aref = @lines;

  } else {
    Paranoid::ERROR = pdebug("error opening file ($file): $!", 9);
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

{
  my %regexes = (
    alphabetic     => qr/[a-zA-Z]+/,
    alphanumeric   => qr/[a-zA-Z0-9]+/,
    alphawhite     => qr/[a-zA-Z\s]+/,
    alnumwhite     => qr/[a-zA-Z0-9\s]+/,
    email          => 
      qr/[a-zA-Z][\w\.\-]*\@(?:[a-zA-Z0-9][a-zA-Z0-9\-]*\.)*[a-zA-Z0-9]+/,
    filename       => qr#[/ \w\-\.:,;]+#,
    hostname       => qr/(?:[a-zA-Z0-9][a-zA-Z0-9\-]*\.)*[a-zA-Z0-9]+/,
    ipaddr         => qr/(?:\d+\.){3}\d+/,
    netaddr        => qr#^(?:\d+\.){3}\d+(?:/(?:\d+|(?:\d+\.){3}\d+))?$#,
    login          => qr/[a-zA-Z][\w\.\-]*/,
    nometa         => qr/[^\%\`\$\!\@]+/,
    number         => qr/[+\-]?[0-9]+(?:\.[0-9]+)?/,
    );

=head2 addTaintRegex

  addTaintRegex("telephone", qr/\(\d{3}\)\s+\d{3}-\d{4}/);

This adds a regular expression which can used by name to detaint user input
via the B<detaint> function.  This will allow you to overwrite the internally
provided regexes or as well as your own.

=cut

  sub addTaintRegex ($$) {
    my $name  = shift;
    my $regex = shift;

    $regexes{$name} = qr/$regex/;
  }

  sub _getTaintRegex ($) {
    my $name = shift;
    return (defined $name && exists $regexes{$name}) ? 
      $regexes{$name} : undef;
  }
}

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
  filename              ^[/ \w\-\.:,;]+$
  hostname              ^(?:[a-zA-Z0-9][a-zA-Z0-9\-]*\.)*
                        [a-zA-Z0-9]+)$
  ipaddr                ^(?:\d+\.){3}\d+$
  netaddr               ^(?:\d+\.){3}\d+(?:/(?:\d+|
                        (?:\d+\.){3}\d+))?$
  login                 ^([a-zA-Z][\w\.\-]*)$
  nometa                ^([^\`\$\!\@]+)$
  number                ^([+\-]?[0-9]+(?:\.[0-9]+)?)$

If the first argument fails to match against these regular expressions the
function will return 0.  This means that zero-length strings or undef values
can B<not> be passed to this function without raising an error.  In fact, the
calling code must validate at least that much before calling this function if
you want to avoid the program croaking.

=cut

sub detaint ($$$) {
  my $input = shift;
  my $type  = shift;
  my $sref  = shift;
  my $rv    = 0;
  my $regex = _getTaintRegex($type);

  # Validate arguments
  croak "No valid input was passed to detain()" unless defined $input &&
    length($input) > 0;
  croak "No valid type was passed to detaint()" unless defined $regex;
  croak "No scalar reference was passed to detaint()"
    unless defined $sref && ref($sref) eq 'SCALAR';

  pdebug("entering w/($input)($type)($sref)", 9);
  pIn();

  # Zero out contents of $sref
  $$sref = undef;

  # Detaint
  ($$sref) = ($input =~ /^($regex)$/m);

  # Report the results
  if (defined($$sref) && length($$sref) > 0) {
    $rv = 1;
    pdebug("detainted value ($$sref)", 9);
  } else {
    pdebug("failed to detaint input", 9);
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 stringMatch

  $rv = stringMatch($input, @strings);

This function does a multiline case insensitive regex match against the 
input for every string passed for matching.  This does safe quoted matches 
(\Q$string\E) for all the strings, unless the string is a perl Regexp 
(defined with qr//) or begins and ends with /.

=cut

sub stringMatch ($@) {
  my $input   = shift;
  my @match   = @_;
  my $rv      = 0;
  my (@regex, $r);

  # Validate arguments
  croak "No valid input was passed to stringMatch()" unless defined $input;
  croak "No valid strings were passed to stringMatch()" unless scalar
    @match;

  pdebug("entering w/($input)(@match)", 9);
  pIn();

  # Populate @regex w/regexes
  @regex = grep { defined $_ && ref($_) eq 'Regexp' } @match;

  # Convert remaining strings to regexes
  foreach (grep { defined $_ && ref($_) ne 'Regexp' } @match) {
    push(@regex, m#^/(.+)/$# ? qr#$1#mi : qr#\Q$_\E#mi);
  }

  # Start comparisons
  foreach $r (@regex) {
    if ($input =~ /$r/mi) {
      $rv = 1;
      last;
    }
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

1;

=head1 HISTORY

None.

=head1 AUTHOR/COPYRIGHT

(c) 2005 Arthur Corliss (corliss@digitalmages.com)

=cut

