# Paranoid::Filesystem -- Filesystem support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Filesystem.pm,v 0.13 2008/08/28 06:33:52 acorliss Exp $
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

Paranoid::Filesystem - Filesystem Functions

=head1 MODULE VERSION

$Id: Filesystem.pm,v 0.13 2008/08/28 06:33:52 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Filesystem;

  $rv = pmkdir("/foo", 0750);
  $rv = prm(\%errors, "/foo", "/bar/*");
  $rv = prmR(\%errors, "/foo/*");

  $rv = preadDir("/etc", \@dirList);
  $rv = psubdirs("/etc", \@dirList);
  $rv = pfiles("/etc", \@filesList);
  $rv = pglob("/usr/*", \@matches); # deprecated
  $rv = pglob(\%errors, \@matches, @globs);

  Paranoid::Filesystem::MAXLINKS = 20;
  $noLinks = ptranslateLink("/etc/foo/bar.conf");
  $cleaned = pcleanPath($filename);

  $rv = ptouch(\%errors, $epoch, @files);
  $rv = ptouchR(1, \%errors, $epoch, @files);

  $rv = ptranslatePerms("ug+rwx");
  $rv = pchmod(\%errors, "ug+rw", "/foo", "./bar*");
  $rv = pchmodR(1, \%errors, $perms, @files);

  $rv = pchown(\%errors, $user, $group, @files);
  $rv = pchownR(1, \%errors, $user, $group, @files);

  $fullname = pwhich('ls');

=head1 REQUIREMENTS

=over

=item o

Cwd

=item o

Paranoid

=item o

Paranoid::Debug

=item o

Paranoid::Input

=back

=head1 DESCRIPTION

This module provides a few functions to make accessing the filesystem a little
easier, while instituting some safety checks.  If you want to enable debug
tracing into each function you must set B<PDEBUG> to at least 9.

B<pcleanPath>, B<ptranslateLink>, and B<ptranslatePerms> are only exported 
if this module is used with the B<:all> target.

B<NOTE:> All of these functions detaint all filename, directory, and glob
arguments using B<detaint> from B<Paranoid::Input>.  If you find the default 
I<filename> or I<fileglob> regexes to be too strict you will have to redefine
them using B<addTaintRegex>.

=cut

#####################################################################
#
# Environment definitions
#
#####################################################################

package Paranoid::Filesystem;

use strict;
use warnings;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
use Exporter;
use Paranoid;
use Paranoid::Debug;
use Paranoid::Process qw(ptranslateUser ptranslateGroup);
use Paranoid::Input;
use Cwd;
use Carp;

($VERSION)    = (q$Revision: 0.13 $ =~ /(\d+(?:\.(\d+))+)/);

@ISA          = qw(Exporter);
@EXPORT       = qw(preadDir     psubdirs    pfiles    pglob 
                   pmkdir       prm         prmR      ptouch
                   ptouchR      pchmod      pchmodR   pchown
                   pchownR      pwhich);
@EXPORT_OK    = qw(preadDir     psubdirs    pfiles    ptranslateLink 
                   pcleanPath   pglob       pmkdir    prm 
                   prmR         ptouch      ptouchR   ptranslatePerms 
                   pchmod       pchmodR     pchown    pchownR
                   pwhich);
%EXPORT_TAGS  = (
  all => [qw(preadDir     psubdirs    pfiles    ptranslateLink 
             pcleanPath   pglob       pmkdir    prm 
             prmR         ptouch      ptouchR   ptranslatePerms 
             pchmod       pchmodR     pchown    pchownR 
             pwhich)],
  );

use constant GLOBCHAR   => '\*\?\{\}\[\]';
use constant GLOBCHECK  => '\*|\?|\{[^\}]*\}|\[[^\]]*\]';
use constant FNINVALID  => '\'"\|\`\$';

#####################################################################
#
# Module code follows
#
#####################################################################

=head1 VARIABLES

=head2 MAXLINKS

  Paranoid::Filesystem::MAXLINKS = 20;

This sets the maximum number of symlinks that will be tolerated in a filename
for translation purposes.  This prevents a runaway process due to circular
references between symlinks.

=cut

{
  my $MAXLINKS = 20;

  sub MAXLINKS : lvalue {
    $MAXLINKS;
  }
}

# Notes:  all recursive programs, with the exception of touch, should exit
# with a false value when called with non-existent values.  touch should
# create those files, assuming the path exists.
#
# Once recursion begins errors for all programs are reported, with the
# assumption that the operation failed for some other reason (no invalid or
# non-existing files should be attempted since pure directory reads should be
# used at that point).

sub _recurseWrapper {
  # This function is a generic wrapper for ptouch, prm, etc., which
  # performs recursive filesystem operations.  It also enables
  # symlink filtering for operations.
  #
  # Usage:  $rv = _recurseWrapper($mode, $followLinks, \%errRef, @args);

  my $mode        = shift;
  my $followLinks = shift || 0;
  my $errRef      = shift;
  my @dargs       = @_;
  my $rv          = 1;
  my ($sref, $op, $i, $o, @expanded);
  my (@ftargets, @tmp, $target, @entries);
  my %subErrors;

  # Remove the timestamp from the args
  if ($mode eq 'pchownR') {
    $op = [ splice(@dargs, 0, 2) ];
  } elsif ($mode ne 'prmR') {
    $op = shift @dargs;
  }
  $o = defined $op ? $op : 'undef';

  pdebug("entering with ($mode)($followLinks)($errRef)($o)(@dargs)", 9);
  pIn();

  # Expand all file arguments
  $rv = pglob(\%subErrors, \@expanded, @dargs);
  %$errRef = ( %$errRef, %subErrors );

  # Check for errors if this is ptouchR
  if ($mode eq 'ptouchR' and scalar keys %subErrors) {
    Paranoid::ERROR = pdebug("invalid glob matches in ptouchR mode", 10);
    $rv = 0;
  }

  # Start recursing into directory entries
  if ($rv) {

    # Process directories
    foreach $target (@expanded) {
      if (($followLinks && -d $target) || 
          (-d $target && ! -l $target)) {

        # Read the directory, if there's results we'll call ourselves
        # recursively.
        if (preadDir("$target", \@entries) && @entries) {
          $rv = _recurseWrapper($mode, $followLinks, \%subErrors, (
            $mode eq 'pchownR' ? (@$op, @entries) :
            $mode ne 'prmR' ? ($op, @entries) : (@entries)));
          %$errRef = ( %$errRef, %subErrors );
        }
      }
    }

    # Perform requested operation
    if ($rv) {

      # Filter out symlinks if requested
      @expanded = grep { ! -l $_ } @expanded unless $followLinks or 
        $mode eq 'prmR';

      # Process list
      if (@expanded) {
        if ($mode eq 'ptouchR') {
          $rv = ptouch(\%subErrors, $op, @expanded);
        } elsif ($mode eq 'prmR') {
          $rv = prm(\%subErrors, @expanded);
        } elsif ($mode eq 'pchmodR') {
          $rv = pchmod(\%subErrors, $op, @expanded);
        } elsif ($mode eq 'pchownR') {
          $rv = pchown(\%subErrors, @$op, @expanded);
        } else {
          Paranoid::ERROR = pdebug("called with unknown " .
            "mode ($mode)", 9);
          $rv = 0;
        }
      }
      %$errRef = (%$errRef, %subErrors) unless $rv;
    }
  }

  pOut();
  pdebug("leaving in mode $mode w/rv: $rv", 9);

  return $rv;
}

=head1 FUNCTIONS

=head2 pmkdir

  $rv = pmkdir("/foo", 0750);

This function simulates a 'mkdir -p {path}', returning false if it fails for
any reason other than the directory already being present.  The second
argument (permissions) is optional, but if present should be an octal number.
Shell-style globs are supported as the path argument.

=cut

sub pmkdir ($;$) {
  my $path    = shift;
  my $mode    = shift;
  my $uarg    = defined $mode ? $mode : 'undef';
  my $rv      = 1;
  my ($dpath, @expanded, @elements, $testPath);

  # Validate arguments
  croak "Mandatory first argument must be a defined path" unless 
    defined $path && length($path);

  pdebug("entering w/($path)($uarg)", 9);
  pIn();

  # Set and detaint mode
  $mode = umask ^ 0777 unless defined $mode;
  unless (detaint($mode, 'number', \$mode)) {
    Paranoid::ERROR = pdebug("failed to detaint mode", 9);
    pOut();
    pdebug("leaving w/rv: $rv", 9);
    return 0;
  }

  # Detaint input and filter through the shell glob
  if (detaint($path, 'fileglob', \$dpath)) {
    $dpath =~ s/@/\\@/g;
    if (eval "\@expanded = <$dpath>") {

      # Create all directories
      foreach (@expanded) {
        if (-d $_) {
          pdebug("directory already exists: $_", 10);
        } else {
          $testPath = '';
          @elements = split(m#/+#, $_);
          $elements[0] = '/' if $_ =~ m#^/#;
          foreach (@elements) {
            $testPath .= '/' if length($testPath);
            $testPath .= $_;
            unless (-d $testPath) {
              if (detaint($testPath, 'filename', \$testPath)) {
                if (mkdir $testPath, $mode) {
                  pdebug("created $testPath", 10);
                } else {
                  $rv = 0;
                  Paranoid::ERROR = pdebug("failed to create $testPath: $!",
                    10);
                  last;
                }
              } else {
                Paranoid::ERROR = pdebug("failed to detaint mkdir args: " .
                  "$testPath $mode", 10);
                $rv = 0;
                last;
              }
            }
          }
        }
      }
    } else {
      Paranoid::ERROR = pdebug("glob failed to eval: $dpath", 9);
      $rv = 0;
    }
  } else {
    Paranoid::ERROR = pdebug("failed to detaint: $path", 9);
    $rv = 0;
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 prm

  $rv = prm(\%errors, "/foo", "/bar/*");

This function unlinks non-directories and rmdir's directories.  File 
arguments are processed through B<pglob> and expanded into multiple
targets if globs are detected.

The error message from each failed operation will be placed into the passed
hash ref using the filename as the key.

NOTE:  If you ask it to delete something that's not there it will silently
succeed.

=cut

sub prm ($@) {
  my $errRef  = shift;
  my @targets = @_;
  my $rv      = 1;
  my (@expanded, @tmp, $target);

  # Validate arguments
  croak "Mandatory first argument must be a hash reference" unless
    defined $errRef && ref($errRef) eq 'HASH';
  croak "Mandatory remaining arguments must be present" unless @targets;
  foreach (@targets) {
    croak "Undefined or zero-length arguments passed as file arguments" unless 
    defined $_ && length($_) > 0 };
  %$errRef = ();

  pdebug("entering w/($errRef)(" . join(', ', @targets) .
    ")", 9);
  pIn();

  # Expand file argument globs
  $rv =  pglob($errRef, \@expanded, @targets);

  # Remove targets
  if ($rv) {
    foreach $target (reverse sort @expanded) {
      pdebug("deleting target $target", 10);

      # Rmdir directories
      if (-d $target && ! -l $target) {
        unless (rmdir $target) {
          Paranoid::ERROR   = pdebug("Failed to delete $target: $!", 10);
          $$errRef{$target} = $!;
          $rv               = 0;
        }

      # Unlink everything else
      } elsif (-e $target || -l $target) {
        unless (unlink $target) {
          Paranoid::ERROR   = pdebug("Failed to delete $target: $!", 10);
          $$errRef{$target} = $!;
          $rv               = 0;
        }
      }
    }
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 prmR

  $rv = prmR(\%errors, "/foo/*");

This function works the same as B<prm> but performs a recursive delete,
similar to "rm -r" on the command line.

=cut

sub prmR ($@) {
  my $errRef      = shift;
  my @targets     = @_;

  # Validate arguments
  croak "Mandatory first argument must be a hash reference" unless
    defined $errRef && ref($errRef) eq 'HASH';
  croak "Mandatory remaining arguments must be present" unless @targets;
  foreach (@targets) {
    croak "Undefined or zero-length arguments passed as file arguments" 
      unless defined $_ && length($_) > 0 };
  %$errRef = ();

  return _recurseWrapper('prmR', 0, $errRef, @targets);
}

=head2 preadDir

  $rv = preadDir("/etc", \@dirList);

This function populates the passed array with the contents of the specified
directory.  If there are any problems reading the directory the return value
will be false and a string explaining the error will be stored in
B<Paranoid::ERROR>.

All entries in the returned list will be prefixed with the directory name.  An
optional third boolean argument can be given to filter out symlinks from the
results.

=cut

sub preadDir ($$;$) {
  my $dir     = shift;
  my $aref    = shift;
  my $noLinks = shift || 0;
  my $rv      = 0;
  local *PREADDIR;
  my $i;

  # Validate arguments
  croak "Mandatory first argument must be a defined directory path" unless
    defined $dir;
  croak "Mandatory second argument must be an array reference" unless
    defined($aref) && ref($aref) eq 'ARRAY';

  pdebug("entering w/($dir)($aref)", 9);
  pIn();
  @$aref = ();

  # Validate directory and exit early, if need be
  unless (-e $dir && -d _ && -r _) {
    if (! -e _) {
      Paranoid::ERROR = pdebug("directory ($dir) does not exist", 9);
    } elsif (! -d _) {
      Paranoid::ERROR = pdebug("$dir is not a directory", 9);
    } else {
      Paranoid::ERROR = pdebug(
        "directory ($dir) is not readable by the effective user", 9);
    }
    pOut();
    pdebug("leaving w/rv: $rv", 9);
    return $rv;
  }

  # Read the directory's contents
  if (opendir(*PREADDIR, $dir)) {

    # Get the list, filtering out '.' & '..'
    @$aref = grep ! /^\.\.?$/, readdir(*PREADDIR);
    closedir(*PREADDIR);

    # Prepend the directory name to each entry
    foreach (@$aref) { $_ = "$dir/$_" };

    # Filter out symlinks, if necessary
    if ($noLinks) {
      for ($i = 0; $i < @$aref; $i++) {
        splice(@$aref, $i, 1) and $i-- if -l $$aref[$i] };
    }

    $rv = 1;
  } else {
    Paranoid::ERROR = pdebug(
      "error opening directory ($dir): $!", 9);
  }
  pdebug("returning @{[ scalar @$aref ]} entries", 9);

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 psubdirs

  $rv = psubdirs("/etc", \@dirList);

This function calls B<preadDir> in the background and filters the list for
directory (or symlinks to) entries.  It also returns a true if the command was
processed with no problems, and false otherwise.

Like B<preadDir> an optional third boolean argument can be passed that causes
symlinks to be filtered out.

=cut

sub psubdirs ($$;$) {
  my $dir     = shift;
  my $aref    = shift;
  my $noLinks = shift || 0;
  my $rv      = 0;
  my @dirList;

  # Validate arguments
  croak "Mandatory first argument must be a defined directory path" unless
    defined $dir;
  croak "Mandatory second argument must be an array reference" unless
    defined($aref) && ref($aref) eq 'ARRAY';

  pdebug("entering w/($dir)($aref)($noLinks)", 9);
  pIn();

  # Empty target array and retrieve list
  @$aref  = ();
  $rv     = preadDir($dir, \@dirList, $noLinks);

  # Filter out all non-directories
  foreach (@dirList) {
    push(@$aref, $_) if -d $_;
  }
  pdebug("returning @{[ scalar @$aref ]} entries", 9);

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 pfiles

  $rv = pfiles("/etc", \@filesList);

This function calls B<preadDir> in the background and filters the list for
file (or symlinks to) entries.  It also returns a true if the command was
processed with no problems, and false otherwise.

Like B<preadDir> an optional third boolean argument can be passed that causes
symlinks to be filtered out.

=cut

sub pfiles ($$;$) {
  my $dir     = shift;
  my $aref    = shift;
  my $noLinks = shift;
  my $rv      = 0;
  my @fileList;

  # Validate arguments
  croak "Mandatory first argument must be a defined directory path" unless
    defined $dir;
  croak "Mandatory second argument must be an array reference" unless
    defined($aref) && ref($aref) eq 'ARRAY';

  pdebug("entering w/($dir)($aref)", 9);
  pIn();

  # Empty target array and retrieve list
  @$aref  = ();
  $rv     = preadDir($dir, \@fileList, $noLinks);

  # Filter out all non-files
  foreach (@fileList) {
    push(@$aref, $_) if -f $_;
  }
  pdebug("returning @{[ scalar @$aref ]} entries", 9);

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 pcleanPath

  $cleaned = pcleanPath($filename);

This function takes a filename and cleans out any '.', '..', and '//+'
occurences within the path.  It does not remove '.' or '..' as the first path
element, however, in order to preserve the root of the relative path.

B<NOTE:> this function does not do any checking to see if the passed
filename/path actually exists or is valid in any way.  It merely removes the
unnecessary artifacts from the string.

If you're resolving an existing filename and want symlinks resolved to the
real path as well you might be interested in B<Cwd>'s B<realpath> function
instead.

=cut

sub pcleanPath ($) {
  my $filename = shift;

  # Validate arguments
  croak "Mandatory first argument must be a defined filename" unless
    defined $filename;

  pdebug("entering w/($filename)", 9);
  pIn();

  # Strip all //+, /./, and /{parent}/../
  while ($filename =~ m#/\.?/+#) { $filename =~ s#/\.?/+#/#g };
  while ($filename =~ m#/(?:(?!\.\.)[^/]{2,}|[^/])/\.\./#) { 
    $filename =~ s#/(?:(?!\.\.)[^/]{2,}|[^/])/\.\./#/#g };

  # Strip trailing /. and leading /../
  $filename =~ s#/\.$##;
  while ($filename =~ m#^/\.\./#) { $filename =~ s#^/\.\./#/# };

  # Strip any ^[^/]+/../
  while ($filename =~ m#^[^/]+/\.\./#) { $filename =~ s#^[^/]+/\.\./## };

  # Strip any trailing /^[^/]+/..$
  while ($filename =~ m#/[^/]+/\.\.$#) { $filename =~ s#/[^/]+/\.\.$## };

  pOut();
  pdebug("leaving w/rv: $filename", 9);

  return $filename;
}

=head2 ptranslateLink

  $noLinks = ptranslateLink("/etc/foo/bar.conf");

This functions tests if passed filename is a symlink, and if so, translates it
to the final target.  If a second argument is passed and evaluates to true it
will check every element in the path and do a full translation to the final
target.

The final target is passed through pcleanPath beforehand to remove any
unneeded path artifacts.  If an error occurs (like exceeding the B<MAXLINKS>
threshold or the target being nonexistent) this function will return undef.
You can retrieve the reason for failure from B<Paranoid::ERROR>.

Obviously, testing for symlinks requires testing against the filesystem, so
the target must be valid and present.

B<Note:> because of the possibility that relative links are being used
(including levels of '..') all links are translated fully qualified from /.

=cut

sub ptranslateLink ($;$) {
  my $link            = shift;
  my $fullyTranslate  = shift || 0;
  my $nLinks          = 0;
  my (@elements, $partial, $i, $j, $target);

  # Validate arguments
  croak "Mandatory first argument must be a defined symlink filename" unless
    defined $link;

  pdebug("entering w/($link)($fullyTranslate)", 9);
  pIn();

  # Validate link and exit early, if need be
  unless (-e $link) {
    Paranoid::ERROR = pdebug(
      "link ($link) or target does not exist on filesystem", 
      9);
    pOut();
    pdebug("leaving w/rv: undef", 9);
    return undef;
  }

  # Check every element in the path for symlinks and translate it if
  # if a full translation was requested
  if ($fullyTranslate) {
    @elements = split(m#/#, $link);

    for ($i = 0; $i < @elements; $i++ ) {
      $partial = join('/', @elements[0..$i]);
      if (-l $partial) {
        ++$nLinks;

        # Make sure we don't exceed our MAXLINKS limit
        unless ($nLinks <= MAXLINKS) {
          Paranoid::ERROR = pdebug("maximum number " .
            "(@{[ MAXLINKS() ]}) of symlinks exceeded", 9);
          pOut();
          pdebug("leaving w/rv: undef", 9);
          return undef;
        }

        $target = readlink $partial;
        pdebug("partial ($partial) is a link to $target", 9);

        # Target's a relative link, we can just replace the current element,
        # otherwise we'll zero out all previous elements to make this the
        # explicitly qualified.
        if ($target =~ m#^/#) {
          for ($j = 0; $j < $i; $j++) { $elements[$j] = '' };
        }
        $elements[$i] = $target;

        # Let's decrement $i so we make sure the new target is checked for
        # being a symlink as well
        $i--;
      }
    }
    $link = join('/', @elements);

  # Otherwise, check only the last element
  } else {
    if (-l $link) {
      $target = readlink $link;
      pdebug("last element is a link to $target", 9);

      # Target's a relative link, so replace just last element
      if ($target =~ m#^(?:\.\.?/|[^/])#) {
        $link =~ s#[^/]+$#$target#;

      # Target's an explicit path, so replace the whole link filename
      } else {
        $link = $target;
      }
    }
  }

  $link = pcleanPath($link);

  pOut();
  pdebug("leaving w/rv: $link", 9);

  return $link;
}

=head2 pglob

  $rv = pglob("/usr/*", \@matches);
  $rv = pglob(\%errors, \@matches, @globs);

This function populates the passed array ref with any matches to the shell 
glob function.  This differs from that function, however, in that it only
returns those files or directories that actually exist on the filesystem.

  *          Expanding wildcard (can be zero-length)
  ?          Single character wildcard (mandatory character)
  [a-z]      Character class
  {foo,bar}  Ellipsis list

This returns a false if there is any problem processing the request, such as
if there is an illegal globbing construct in the request or other types of
errors.  B<Paranoid::ERROR> will store a string explaining the failure, as
well as an associated value in the passed hash reference (in the latter
calling incarnation).

Two forms of the function call are supported, primarily for backward
compatibility purposes.  The latter is the prefered incarnation.

=cut

sub pglob ($@) {
  my @args  = @_;
  my $rv    = 1;
  my ($glob, $href, $aref, @tmp, $f);

  # Validate arguments
  croak "Mandatory first argument must be a defined glob or a " .
    "hash reference" unless defined $args[0] and 
    (ref($args[0]) eq 'HASH' or length($args[0]));

  # New calling format
  if (ref($args[0]) eq 'HASH') {
    croak "Mandatory second argument must be an array reference" unless
      ref($args[1]) eq 'ARRAY';
    croak "Mandatory third argument must be a defined file glob" unless
      defined $args[2];

  # Old calling format
  } else {
    croak "Mandatory first argument must be a defined file glob" unless
      defined $args[0];
    croak "Mandatory second argument must be an array reference" unless
      ref($args[1]) eq 'ARRAY';
  }

  pdebug("entering w/(@args)", 9);
  pIn();

  # Figure out which calling form we're using
  if (ref($args[0]) eq 'HASH') {
    $href   = shift @args;
    $aref   = shift @args;
    %$href  = ();
  } else {
    $glob   = shift @args;
    $aref   = shift @args;
    @args   = ($glob);
    $href   = {};
  }
  @$aref = ();

  # Process each glob
  foreach (@args) {
    if (detaint($_, 'fileglob', \$glob)) {
      $glob =~ s/@/\\@/g;
      if (eval "\@tmp = <$glob>") {

        # Go through the shell glob results and test for the
        # existence of each file, pushing only those that exist
        # onto the array
        foreach (@tmp) {
          if (detaint($_, 'filename', \$f)) {
            if (-l $f or -e _) {
              push(@$aref, $f);
            } else {
              $$href{$f} = "file not found";
            }
          } else {
            Paranoid::ERROR = 
              pdebug("return value from glob failed to detaint: $_", 10);
            $$href{$_} = "return value from glob failed to detaint";
            $rv = 0;
          }
        }
        pdebug("Matches from glob: @$aref", 10);
      } else {
        Paranoid::ERROR = $$href{$glob} = 
          pdebug("glob failed to eval:  $glob", 9);
        $rv = 0;
      }
    } else {
      Paranoid::ERROR = pdebug("glob failed to detaint:  $_", 9);
      $$href{$_} = "glob failed to detaint";
      $rv = 0;
    }
  }

  pdebug("returning @{[ scalar @$aref ]} matches", 9);

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 ptouch

  $rv = ptouch(\%errors, $epoch, @files);

Simulates the UNIX touch command.  Like the UNIX command this will create
zero-byte files if they don't exist.  The first argument is the timestamp to
apply to targets.  If undefined it will default to the current value of
time().

Shell-style globs are supported.

The error message from each failed operation will be placed into the passed
hash ref using the filename as the key.

=cut

sub ptouch ($$@) {
  my $errRef  = shift;
  my $stamp   = shift;
  my @targets = @_;
  my $sarg    = defined $stamp ? $stamp : 'undef';
  my $rv      = 1;
  my ($fd, @expanded, $glob, @tmp, $target);

  # Validate arguments
  croak "Mandatory first argument must be an array reference" unless
    defined $errRef && ref($errRef) eq 'HASH';
  croak "Mandatory remaining arguments must have at least one target" unless
    @targets;
  foreach (@targets) {
    croak "Undefined or zero-length arguments passed as file arguments " .
      "to ptouch()" unless defined $_ && length($_) > 0 };
  %$errRef = ();

  pdebug("entering w/($errRef)($sarg)(" . join(', ', 
    @targets) . ")", 9);
  pIn();

  # Apply the default timestamp if omitted
  $stamp = time() unless defined $stamp;

  # Detaint args and filter through the shell glob
  foreach (@targets) {
    if (detaint($_, 'fileglob', \$glob)) {
      $glob =~ s/@/\\@/g;
      if (eval "\@tmp = <$glob>") {
        push(@expanded, @tmp);
      } else {
        Paranoid::ERROR = $$errRef{$glob} = $$errRef{$glob} = 
          pdebug("glob failed to eval: $glob", 9);
        $rv = 0;
      }
    } else {
      Paranoid::ERROR = $$errRef{$_} = pdebug("failed to detaint $_", 10);
      $rv = 0;
    }
  }

  # Touch the final targets
  if ($rv) {
    foreach $target (@expanded) {
      pdebug("processing target $target", 10);

      # Make sure there's not meta characters
      if (detaint($target, 'filename', \$glob)) {
        $target = $glob;

        # Create the target if it does not exist
        unless (-e $target) {
          pdebug("creating empty file ($target)", 10);
          if (open($fd, ">>$target")) {
            close($fd);
          } else {
            $$errRef{$target} = $!;
            $rv = 0;
          }
        }

        # Touch the file
        if (detaint($stamp, 'number', \$glob)) {
          $stamp = $glob;
          $rv = utime $stamp, $stamp, $target if $rv;
        } else {
          Paranoid::ERROR =
            pdebug("Invalid characters in timestamp: $stamp", 10);
          $rv = 0;
        }
      } else {
        Paranoid::ERROR = $$errRef{$target} = 
          pdebug("Invalid characters in filename: $target", 10);
        $rv = 0;
      }
    }
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 ptouchR

  $rv = ptouchR(1, \%errors, $epoch, @files);

This function works the same as B<ptouch>, but requires one additional
argument (the first argument), boolean, which indicates whether or not the
command should follow symlinks.

You cannot use this function to create new, non-existant files, this only
works to update an existing directory heirarchy's mtime.

=cut

sub ptouchR ($$$@) {
  my $followLinks = shift;
  my $errRef      = shift;
  my $stamp       = shift;
  my @targets     = @_;

  # Validate arguments
  croak "Mandatory second argument must be a hash reference" unless
    defined $errRef && ref($errRef) eq 'HASH';
  croak "Mandatory remaing arguments must be at least one target" unless
    @targets;
  foreach (@targets) {
    croak "Undefined or zero-length arguments passed as file arguments " .
      "to ptouchR()" unless defined $_ && length($_) > 0 };
  %$errRef = ();

  return _recurseWrapper('ptouchR', $followLinks, $errRef, $stamp, @targets);
}

=head2 ptranslatePerms

  $rv = ptranslatePerms("ug+rwx");

This translates symbolic mode notation into an octal number.  It fed invalid 
permissions it will return undef.  It understands the following symbols:

  u            permissions apply to user
  g            permissions apply to group
  o            permissions apply to all others
  r            read privileges
  w            write privileges
  x            execute privileges
  s            setuid/setgid (depending on u/g)
  t            sticky bit

B<EXAMPLES>

  # Add user executable privileges
  $perms = (stat "./foo")[2];
  chmod $perms | ptranslatePerms("u+x"), "./foo";

  # Remove all world privileges
  $perms = (stat "./bar")[2];
  chmod $perms ^ ptranslatePerms("o-rwx"), "./bar";

=cut

sub ptranslatePerms ($) {
  my $perm  = shift;
  my $rv    = undef;
  my (@tmp, $o, $p);

  # Validate arguments
  croak "Mandatory first argument must be a defined permissions string" unless
    defined $perm;

  pdebug("entering w/($perm)", 9);
  pIn();

  # Translate symbolic representation
  if ($perm =~ /^([ugo]+)([+\-])([rwxst]+)$/) {
    $o = $p = 00;
    @tmp = ($1, $2, $3);
    $o  = 0700 if $tmp[0] =~ /u/;
    $o |= 0070 if $tmp[0] =~ /g/;
    $o |= 0007 if $tmp[0] =~ /o/;
    $p  = 0444 if $tmp[2] =~ /r/;
    $p |= 0222 if $tmp[2] =~ /w/;
    $p |= 0111 if $tmp[2] =~ /x/;
    $p &= $o;
    $p |= 01000 if $tmp[2] =~ /t/;
    $p |= 02000 if $tmp[2] =~ /s/ && $tmp[0] =~ /g/;
    $p |= 04000 if $tmp[2] =~ /s/ && $tmp[0] =~ /u/;

  # Return the error
  } else {
    Paranoid::ERROR = pdebug("invalid permissions " .
      "($perm)", 9);
  }
  $rv = $p;

  pOut();
  pdebug((defined $rv ? sprintf("leaving w/rv: %04o", $rv) : 
    'leaving w/rv: undef'), 9);

  return $rv;
}

=head2 pchmod

  $rv = pchmod(\%errors, "ug+rw", "/foo", "./bar*");

This function takes a given permission and applies it to every file given to
it.  The permission can be an octal number or symbolic notation (see 
B<ptranslatePerms> for specifics).  If symbolic notation is used the
permissions will be applied relative to the current permissions on each
file.  In other words, it acts exactly like the B<chmod> program.

File arguments are processed through B<pglob> and expanded into multiple
targets if globs are detected.

The error message from each failed operation will be placed into the passed
hash ref using the filename as the key.

The return value will be true unless any errors occur during the actual
chmod operation including attempting to set permissions on non-existent
files.  

=cut

sub pchmod ($$@) {
  my $errRef  = shift;
  my $perms   = shift;
  my @targets = @_;
  my $rv      = 0;
  my ($ptrans, $target, $cperms, $addPerms, @expanded, @tmp);

  # Validate arguments
  croak "Mandatory first argument must be a hash reference" unless
    defined $errRef && ref($errRef) eq 'HASH';
  croak "Mandatory second argument must a defined permissions string" unless
    defined $perms;
  croak "Mandatory remaining arguments must have at least one target" unless
    @targets;
  foreach (@targets) {
    croak "Undefined or zero-length arguments passed as file arguments " .
      "to pchmod()" unless defined $_ && length($_) > 0 };
  %$errRef = ();

  pdebug("entering w/($errRef)($perms)(" . 
    join(', ', @targets) . ")", 9);
  pIn();

  # Convert perms if they're symbolic
  $ptrans = ptranslatePerms($perms);
  if (defined $ptrans) {
    $addPerms = $perms =~ /-/ ? 0 : 1;
  }

  # Expand file argument globs and check for mismatches
  $rv = pglob($errRef, \@expanded, @targets);
  if (scalar keys %$errRef) {
    Paranoid::ERROR = pdebug("invalid glob matches", 10);
    $rv = 0;
  }

  # Apply permissions to final list of targets
  if ($rv) {

    foreach $target (@expanded) {
      pdebug("processing target $target", 10);

      # Skip non-existent targets
      unless (-e $target) {
        pdebug("target missing: $target", 10);
        $$errRef{$target} = 'file not found';
        next;
      }

      # If ptrans is defined we're going to do relative application
      # of permissions
      if (defined $ptrans) {
        pdebug($addPerms ? sprintf("adding perms %04o", $ptrans) :
          sprintf("removing perms %04o", $ptrans), 10);

        # Get the current permissions
        $cperms = (stat $target)[2] & 07777;
        pdebug(sprintf("current permissions of $target: %04o", $cperms), 10);
        $cperms = $addPerms ? ($cperms | $ptrans) : 
            ($cperms & (07777 ^ $ptrans));
        pdebug(sprintf("new permissions of $target: %04o", $cperms), 10);
        $rv = chmod $cperms, $target;
        $$errRef{$target} = $! unless $rv;

      # Otherwise, the permissions are explicit
      } else {
        if (detaint($perms, 'number', \$perms)) {
          pdebug(sprintf("changing to perms %04o", $perms), 10);
          $rv = chmod $perms, $target;
          $$errRef{$target} = $! unless $rv;
        } else {
          Paranoid::ERROR = $$errRef{$target} = 
            pdebug("failed to detaint permissions mode", 9);
          $rv = 0;
        }
      }
    }

    # Report the errors
    if (scalar keys %$errRef) {
      Paranoid::ERROR = pdebug("errors occured while applying " .
        "permissions", 9);
      $rv = 0;
    }
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 pchmodR

  $rv = pchmodR(1, \%errors, $perms, @files);

This function works the same as B<pchmod>, but requires one additional
argument (the first argument), boolean, which indicates whether or not the
command should follow symlinks.

=cut

sub pchmodR ($$$@) {
  my $followLinks = shift;
  my $errRef      = shift;
  my $perms       = shift;
  my @targets     = @_;

  # Validate arguments
  croak "Mandatory second argument must be an array reference" unless
    defined $errRef && ref($errRef) eq 'HASH';
  croak "Mandatory third argument must be a defined permissions string"
    unless defined $perms;
  croak "Mandatory remaining arguments must be a least one target" unless
    @targets;
  foreach (@targets) {
    croak "Undefined or zero-length arguments passed as file arguments " .
      "to pchmodR()" unless defined $_ && length($_) > 0 };
  %$errRef = ();

  return _recurseWrapper('pchmodR', $followLinks, $errRef, $perms, 
    @targets);
}

=head2 pchown

  $rv = pchown(\%errors, $user, $group, @files);

This function takes a user and/or a named group or ID and applies it to
every file given to it.  If either the user or group is undefined it leaves
that portion of ownership unchanged.

File arguments are processed through B<pglob> and expanded into multiple
targets if globs are detected.

The error message from each failed operation will be placed into the passed
hash ref using the filename as the key.

The return value will be true unless any errors occur during the actual
chown operation including attempting to set permissions on non-existent
files.  

=cut

sub pchown ($$$@) {
  my $errRef    = shift;
  my $user      = shift;
  my $group     = shift;
  my @targets   = @_;
  my $rv        = 0;
  my ($uuid, $ugid, @pwentry, @expanded, @tmp, $target, $t);

  # Validate arguments
  croak "Mandatory first argument must be a hash reference" unless
    defined $errRef && ref($errRef) eq 'HASH';
  croak "Mandatory second or third argument must be a defined user or " .
    "group" unless defined $user || defined $group;
  croak "Mandatory remaining arguments must be at least one target" unless
    @targets;
  foreach (@targets) {
    croak "Undefined or zero-length arguments passed as file arguments " .
      "to pchown()" unless defined $_ && length($_) > 0 };
  %$errRef = ();

  $user = -1 unless defined $user;
  $group = -1 unless defined $group;

  pdebug("entering w/($errRef)($user)($group)(" . join(', ',
    @targets) . ')', 9);
  pIn();

  # Translate to UID
  $user = ptranslateUser($user) unless $user =~ /^-?\d+$/;

  # Translate to GID
  $group = ptranslateGroup($group) unless $group =~ /^-?\d+$/;

  # Proceed if we've successfully translated to UID/GID
  if (defined $user && defined $group) {
    pdebug("UID: $user GID: $group", 10);

    # Expand file argument globs
    $rv = pglob($errRef, \@expanded, @targets);
    if (scalar keys %$errRef) {
      Paranoid::ERROR = pdebug("invalid glob matches", 10);
      $rv = 0;
    }

    # Process the list
    foreach $target (@expanded) {
      $t = $target;
      if (detaint($target, 'filename', \$target)) {
        pdebug("processing target $target", 10);
        $rv = chown $user, $group, $target;
        $$errRef{$target} = $! unless $rv;
      } else {
        $$errRef{$t} = "error detainting directory" unless $rv;
        $rv = 0;
      }
    }

    # Report the errors
    if (scalar keys %$errRef) {
      Paranoid::ERROR = pdebug("errors occured while applying " .
        "ownership", 9);
      $rv = 0;
    }

  # Log the error
  } else {
    Paranoid::ERROR = pdebug("unsuccessful at translating uid/gid",
      9);
  }

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 pchownR

  $rv = pchownR(1, \%errors, $user, $group, @files);

This function works the same as B<pchown>, but requires one additional
argument (the first argument), boolean, which indicates whether or not the
command should follow symlinks.

=cut

sub pchownR ($$$$@) {
  my $followLinks = shift;
  my $errRef      = shift;
  my $user        = shift;
  my $group       = shift;
  my @targets     = @_;

  # Validate arguments
  croak "Mandatory second argument must be a hash reference" unless
    defined $errRef && ref($errRef) eq 'HASH';
  croak "Mandatory third or fourth argument must be a defined user or " .
    "group" unless defined $user || defined $group;
  croak "Mandatory remaining arguments must be at least one target" unless
    @targets;
  foreach (@targets) {
    croak "Undefined or zero-length arguments passed as file arguments " .
      "to pchownR()" unless defined $_ && length($_) > 0 };
  %$errRef = ();

  return _recurseWrapper('pchownR', $followLinks, $errRef, $user, $group, 
    @targets);
}

=head2 pwhich

  $fullname = pwhich('ls');

This function tests each directory in your path for a binary that's both
readable and executable by the effective user.  It will return only one
match, stopping the search on the first match.  If no matches are found it
will return undef.

=cut

sub pwhich ($) {
  my $binary      = shift;
  my @directories = grep /^.+$/, split(/:/, $ENV{PATH});
  my $match       = undef;
  my $b;

  # Validate args
  croak "Mandatory first argument must be a defined binary name" unless
    defined $binary;

  pdebug("entering w/($binary)", 9);
  pIn();

  # detaint binary name
  if (detaint($binary, 'filename', \$b)) {
    foreach (@directories) {
      pdebug("searching $_", 10);
      if (-r "$_/$b" && -x _) {
        $match = "$_/$b";
        $match =~ s#/+#/#g;
        last;
      }
    }

  # Report errors
  } else {
    Paranoid::ERROR = pdebug("failed to detaint $binary", 10);
  }

  pOut();
  pdebug("leaving w/rv: " . (defined $match ? $match : 'undef'), 9);

  return $match;
}

1;

=head1 HISTORY

None as of yet.

=head1 AUTHOR/COPYRIGHT

(c) 2005 Arthur Corliss (corliss@digitalmages.com)

=cut

