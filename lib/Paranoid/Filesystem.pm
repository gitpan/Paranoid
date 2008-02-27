# Paranoid::Filesystem -- Filesystem support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Filesystem.pm,v 0.11 2008/02/27 06:48:12 acorliss Exp $
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

Paraniod::Filesystem - Filesystem Functions

=head1 MODULE VERSION

$Id: Filesystem.pm,v 0.11 2008/02/27 06:48:12 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Filesystem;

  $rv = pmkdir("/foo", 0750);
  $rv = prm(\%errors, "/foo", "/bar/*");
  $rv = prmR(\%errors, "/foo/*");

  $rv = preadDir("/etc", \@dirList);
  $rv = psubdirs("/etc", \@dirList);
  $rv = pfiles("/etc", \@filesList);
  $rv = pglob("/usr/*", \@matches);

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

Cwd
Paranoid
Paranoid::Debug

=head1 DESCRIPTION

This module provides a few functions to make accessing the filesystem a little
easier, while instituting some safety checks.  If you want to enable debug
tracing into each function you must set B<PDEBUG> to at least 9.

B<pcleanPath>, B<ptranslateLink>, and B<ptranslatePerms> are only exported 
if this module is used with the B<:all> target.

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
use Cwd;
use Carp;

($VERSION)    = (q$Revision: 0.11 $ =~ /(\d+(?:\.(\d+))+)/);

@ISA          = qw(Exporter);
@EXPORT       = qw(preadDir psubdirs pfiles pglob pmkdir 
                   prm prmR ptouch ptouchR pchmod pchmodR pchown
                   pchownR pwhich);
@EXPORT_OK    = qw(preadDir psubdirs pfiles ptranslateLink 
                   pcleanPath pglob pmkdir prm prmR ptouch ptouchR
                   ptranslatePerms pchmod pchmodR pchown pchownR
                   pwhich);
%EXPORT_TAGS  = (
  all => [qw(preadDir psubdirs pfiles ptranslateLink pcleanPath 
             pglob pmkdir prm prmR ptouch ptouchR ptranslatePerms 
             pchmod pchmodR pchown pchownR pwhich)],
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

sub _recurseWrapper {
  # This function is a generic wrapper for ptouch, prm, etc., which
  # performs recursive filesystem operations.  It also enables
  # symlink filtering for operations.
  #
  # Usage:  $rv = _recurseWrapper($mode, $followLinks, \%errRef, @args);

  my $mode        = shift;
  my $followLinks = shift;
  my $errRef      = shift;
  my @args        = @_;
  my ($rv, $sref, $op);
  my (@ftargets, @tmp, $target);
  my %subErrors;

  # Remove the timestamp from the args
  if ($mode eq 'pchownR') {
    $op = [ shift(@args), shift(@args) ];
  } elsif ($mode ne 'prmR') {
    $op = shift @args;
  }

  pdebug("entering in mode $mode with args (@args)", 9);
  pIn();

  # Expand all file arguments
  foreach (@args) {
    $rv = pglob($_, \@tmp);
    $rv = 0 unless @tmp || $mode eq 'ptouchR';
    last unless $rv;
    @tmp = ($_) if ! @tmp && $mode eq 'ptouchR';
    push(@ftargets, @tmp);
  }

  # Start recursing into directory entries
  if ($rv) {
    foreach $target (@ftargets) {

      # Process directories
      if (($followLinks && -d $target) || 
          (-d $target && ! -l $target)) {

        # Call ourselves recursively
        $rv = _recurseWrapper($mode, $followLinks, \%subErrors, (
          $mode eq 'pchownR' ? (@$op, "$target/*") :
          $mode ne 'prmR' ? ($op, "$target/*") : ("$target/*")));
        %$errRef = (%subErrors);
      }
    }

    # Perform requested operation
    if ($rv) {

      # Filter out symlinks if requested
      @ftargets = grep { ! -l $_ } @ftargets unless $followLinks or 
        $mode eq 'prmR';

      # Process list
      if (@ftargets) {
        if ($mode eq 'ptouchR') {
          $rv = ptouch(\%subErrors, $op, @ftargets);
        } elsif ($mode eq 'prmR') {
          $rv = prm(\%subErrors, @ftargets);
        } elsif ($mode eq 'pchmodR') {
          $rv = pchmod(\%subErrors, $op, @ftargets);
        } elsif ($mode eq 'pchownR') {
          $rv = pchown(\%subErrors, @$op, @ftargets);
        } else {
          Paranoid::ERROR = pdebug("called with unknown " .
            "mode ($mode)", 9);
          $rv = 0;
        }
      }
      %$errRef = (%$errRef, %subErrors) unless $rv;
    }

  # prm always succeeds if the targets are already gone
  } elsif ($mode eq 'prmR' && @ftargets == 0) {
    $rv = 1;
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

=cut

sub pmkdir ($;$) {
  my $path    = shift;
  my $mode    = shift;
  my $uarg    = defined $mode ? $mode : 'undef';
  my $rv      = 1;
  my (@elements, $testPath);

  # Validate arguments
  croak "No path was passed to pmkdir()" unless defined $path;
  croak "Zero-length path passed to pmkdir()" unless length($path) > 0;

  pdebug("entering w/($path)($uarg)", 9);
  pIn();

  $mode = umask ^ 0777 unless defined $mode;

  $path = pcleanPath($path);
  @elements = split(m#/#, $path);
  if (! defined $elements[0] || length($elements[0]) == 0) {
    shift @elements;
    $elements[0] = "/$elements[0]";
  }
  foreach (@elements) {
    $testPath = defined $testPath ? "$testPath/$_" : $_;
    if (! -d $testPath) {
      pdebug("path $testPath is not present -- creating", 10);
      unless (mkdir $testPath, $mode) {
        Paranoid::ERROR = pdebug("failed to create $testPath: $!", 9);
        $rv = 0;
        last;
      }
    } else {
      pdebug("path $testPath is present", 10);
    }
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
  my $rv      = 0;
  my (@ftargets, @tmp, $target);

  # Validate arguments
  croak "Invalid error hash reference passed to prm()" unless 
    defined $errRef && ref($errRef) eq 'HASH';
  croak "No targets passed to prm()" unless @targets;
  foreach (@targets) {
    croak "Undefined or zero-length arguments passed as file arguments " .
      "to prm()" unless defined $_ && length($_) > 0 };
  %$errRef = ();

  pdebug("entering w/($errRef)(" . join(', ', @targets) .
    ")", 9);
  pIn();

  # Expand file argument globs
  foreach (@targets) {
    $rv = pglob($_, \@tmp);
    last unless $rv;
    push(@ftargets, @tmp);
  }

  # Remove targets
  if ($rv) {
    foreach $target (@ftargets) {
      pdebug("deleting target $target", 10);

      # Rmdir directories
      if (-d $target && ! -l $target) {
        unless (rmdir $target) {
          $$errRef{$target} = $!;
          $rv = 0;
        }

      # Unlink everything else
      } elsif (-e $target || -l $target) {
        unless (unlink $target) {
          $$errRef{$target} = $!;
          $rv = 0;
        }
      }
    }
  }

  Paranoid::ERROR = pdebug("errors occurred during processing", 9) if
    scalar keys %$errRef;

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head2 prmR

  $rv = prmR(\%errors, "/foo/*");

This function works the same as B<prm> but performs a recursive delete,
similar to "rm -r" on the command line.

=cut

sub prmR ($$@) {
  my $errRef      = shift;
  my @targets     = @_;

  # Validate arguments
  croak "Invalid error hash reference passed to prmR()" unless 
    defined $errRef && ref($errRef) eq 'HASH';
  croak "No targets passed to prmR()" unless @targets;
  foreach (@targets) {
    croak "Undefined or zero-length arguments passed as file arguments " .
      "to prmR()" unless defined $_ && length($_) > 0 };
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
  croak "No directory argument was passed to slurp()"
    unless defined $dir;
  croak "No array reference was passed to slurp()"
    unless defined($aref) && ref($aref) eq 'ARRAY';

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
  croak "No directory argument was passed tp psubdirs()" unless
    defined $dir;
  croak "No array reference was passed to psubdirs()" unless
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
  croak "No directory argument was passed tp pfiles()" unless
    defined $dir;
  croak "No array reference was passed to pfiles()" unless
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
  croak "No filename was passed to pcleanPath()" unless defined $filename;

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
  croak "No link filename was passed to ptranslateLink()" unless
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

sub _globRegex ($$) {
  # Takes a glob string and a scalar ref in which it will store a 
  # regex string that equates to the shell glob.  This will return
  # true or false, depending on whether the glob translation was
  # successful.
  #
  # No support for embedded globbing constructs at this time, or 
  # directory slashes in ellipsis lists.
  #
  # Usage:  $rv = _globRegex($glob, \$sregex);

  my $glob  = shift;
  my $sref  = shift;
  my $rv    = 1;
  my $particle;

  pdebug("entering w/($glob)($sref)", 10);
  pIn();

  # Match on the various glob constructs
  if ($glob eq '*') {
    $$sref = '.*';
  } elsif ($glob eq '?') {
    $$sref = '.';
  } elsif ($glob =~ /^\[(.*)\]$/) {
    $particle = $1;
    if ($particle =~ /[@{[ GLOBCHAR ]}]/) {
      pdebug("illegal characters within a character " .
        "class ($particle)", 10);
      $rv = 0;
    } else {
      $$sref = "[$particle]";
    }
  } elsif ($glob =~ /^\{(.*)\}$/) {
    $particle = $1;
    if ($particle =~ m#[@{[ GLOBCHAR ]}/]#) {
      pdebug("illegal characters within an ellipsis " .
        "list ($particle)", 10);
      $rv = 0;
    } else {
      $$sref = '(?:' . join('|', split(/,/, $particle)) . ')';
    }

  # If we've gotten to here we've either been giving something with
  # no glob characters (which is safe) or it's an incomplete 
  # construct, which is bad.
  } else {
    if ($glob =~ /[@{[ GLOBCHAR ]}]/) {
      pdebug("incomplete globbing construct", 10);
      $rv = 0;
    } else {
      $$sref = $glob;
    }
  }

  pOut();
  pdebug("leaving w/rv: $rv", 10);

  return $rv;
}

sub _addFsLevel {
  # Adds another level to the hash of hashes if it exists on the file
  # system. otherwise it prunes dead-end branches.  The third argument
  # should be either 'glob' or 'nonglob'.  The second hash ref is used
  # store directory listings for this pglob call only, in order to
  # reduce disk I/O wasted on redundant directory reads.
  #
  # Usage:  _addFsLevel(\%fs, \%cache, "nonglob", "foo", "/usr");

  my $href    = shift;
  my $chref   = shift;
  my $type    = shift;
  my $element = shift;
  my $path    = shift || '';
  my $rv      = 0;
  my ($internalPath, @dirList);

  pdebug("entering w/($href)($type)($element)", 10);
  pIn();
  $path =~ s#\\\.#.#g;

  # If the ref we're handed is already populated then we need to recurse
  # into each subhash until it finds the bottom of each branch
  if (scalar keys %$href) {
    foreach (keys %$href) {

      # If we get a true value out it must have found and added
      # a new element.  If it returns a false, it means it didn't,
      # so we need to consider pruning this branch.
      $internalPath = $path eq '' ? $_ : "$path$_";
      pdebug("recursing into hash for ($internalPath)", 10);
      unless (_addFsLevel($$href{$_}, $chref, $type, $element, 
        "$internalPath")) {
        pdebug("pruning dead-end ($internalPath)", 10);
        delete $$href{$_};
      }
    }

    # Return a true value only if we still have some branches left
    # that aren't yet dead-ends
    $rv = 1 if scalar keys %$href;

  # We must have found the bottom of the branch, so let's start
  # looking for matches
  } else {

    # Test nonglob entries directly
    if ($type eq 'nonglob') {
      $element =~ s#\\\.#.#g;
      $path .= $element;
      if (-e $path) {
        pdebug("adding new element ($element)", 10);
        $$href{$element} = {};
        $rv = 1;
      }

    # Do a preadDir for globs and matches
    } else {

      # We can only glob what we can read
      if (-d $path) {

        # Get the directory contents from the cache, if possible
        if (exists $$chref{$path}) {
          @dirList = @{ $$chref{$path} };
        } else {
          preadDir($path, \@dirList);
          $$chref{$path} = [ @dirList ];
        }

        if (@dirList) {

          # Filter only matches
          foreach (@dirList) {
            s#^\Q$path\E/*##;
          }
          @dirList = grep /^$element$/, @dirList;
          $rv = 1 if @dirList;
          foreach (@dirList) {
            pdebug("adding new element ($_)", 10);
            $$href{$_} = {};
          }
        }

      # If our current path isn't a directory then this must be a bad
      # match
      } else {
        Paranoid::ERROR = pdebug(
          "($path) is not a directory", 10);
      }
    }
  }

  pOut;
  pdebug("leaving w/rv: $rv", 10);

  return $rv;
}

sub _lsFs {
  # Recursively descends into a hash of hashes until it dead-ends,
  # at which point it will populate the passed array reference with
  # an assembled string of all hash keys in the path to this hash
  # concatenated together.
  #
  # Usage:  _lsFs(\%fs, \@files);

  my $href = shift;
  my $aref = shift;
  my $path = shift || '';
  my @keys = keys %$href;
  my $internalPath;

  foreach (@keys) {
    $internalPath = $path eq '' ? $_ : "$path$_";
    if (scalar keys %{ $$href{$_} }) {
      _lsFs($$href{$_}, $aref, $internalPath);
    } else {
      push(@$aref, $internalPath);
    }
  }
}

=head2 pglob

  $rv = pglob("/usr/*", \@matches);

This function populates the passed array ref with any matches to the shell 
glob.  The glob is a shell-style glob, but only a subset of the syntax is
currently supported.

  *          Expanding wildcard (can be zero-length)
  ?          Single character wildcard (mandatory character)
  [a-z]      Character class
  {foo,bar}  Ellipsis list

Shell meta-characters are not supported as filename characters (escaped), nor
are back ticks, quotes, dollar and signs.  Embedding globbing constructs
within other constructs (like having a character class as part of a list
element within an ellipsis) is not supported, nor are directory elements
within ellipsis.

This returns a false if there is any problem processing the request, such as
if there is an illegal globbing construct in the request or other types of
errors.  B<Paranoid::ERROR> will store a string explaining the failure.

=cut

sub pglob ($$) {
  my $glob  = shift;
  my $aref  = shift;
  my $rv    = 0;
  my (@section, @rsection, %fs, %cache, $segment);
  my ($ng, $g1, $r);

  # Validate arguments
  croak "No valid glob was passed to pglob()" unless defined $glob;
  croak "No valid array reference was passed to pglob()" unless
    defined($aref) && ref($aref) eq 'ARRAY';

  @$aref = ();
  pdebug("entering w/($glob)", 9);
  pIn();

  # Test for invalid characters
  if ($glob =~ /[@{[ FNINVALID ]}]/) {
    Paranoid::ERROR = pdebug("invalid characters in glob ($glob)", 9);

  # Or test for no globs
  } elsif ($glob !~ /[@{[ GLOBCHAR ]}]/) {
    push(@$aref, $glob) if -e $glob || -l $glob;
    $rv = 1;

  # Otherwise, process globs
  } else {

    # Preemptively escape '.'s for regex correctness
    $glob =~ s/\./\\./g;

    # Pull apart glob & non-glob sections
    while (defined $glob) {
      ($ng, $g1, $r) = ($glob =~ 
        m#^( [^@{[ GLOBCHAR ]}]*/ )?
           ( [^/@{[ GLOBCHAR ]}]*
             (?: @{[ GLOBCHECK ]} )
             [^/@{[ GLOBCHAR ]}]* )? 
           (.+)?
             $#x);   
      push(@section, $ng) if defined $ng;
      push(@section, $g1) if defined $g1;
      $glob = $r;
      pdebug("got non-glob section ($ng)", 10) if defined $ng;
      pdebug("got glob section ($g1)", 10) if defined $g1;
      pdebug("still have remainder to process ($r)", 10) if
        defined $r;
    }

    # Convert globs in @section into consolidated regexes
    while (@section) {

      # Combine non-glob sections
      $segment = '';
      while (@section && $section[0] !~ /[@{[ GLOBCHAR ]}]/) {
        $segment .= shift @section;
      }
      push(@rsection, ['nonglob', $segment]) if length($segment) > 0;
      pdebug("flattened segments into ($segment)", 10) if
        length($segment) > 0;

      # Combine glob sections
      $segment = '';
      while (@section && ($section[0] =~ m#[@{[ GLOBCHAR ]}]# || 
        $section[0] !~ m#/#)) {

        # Transform globs into regexes
        if ($section[0] =~ /[@{[ GLOBCHAR ]}]/) {

          # Make sure a valid regex could be made
          $section[0] =~ m#
            ([^@{[ GLOBCHAR ]}]*)
            (@{[ GLOBCHECK ]})
            ([^@{[ GLOBCHAR ]}]*)?
            $#x;
          ($ng, $g1, $r) = ($1, $2, $3);
          if ($section[0] =~ /@{[ GLOBCHECK ]}/ && 
            _globRegex($g1, \$g1)) {
            $segment .= $ng if defined $ng;
            $segment .= $g1;
            $segment .= $r if defined $r;
            shift @section;

          # or exit
          } else {
            Paranoid::ERROR = pdebug("invalid or unsupported " .
              "globbing construct in glob", 9);
            pOut();
            pdebug("leaving w/rv: $rv", 9);
            return $rv;
          }

        # Just append non-glob portions
        } else {
          $segment .= shift @section;
        }
      }
      push(@rsection, ['glob', $segment]) if length($segment) > 0;
      pdebug("flattened segments into ($segment)", 10) if
        length($segment) > 0;
    }

    # Search for files/dirs
    foreach (@rsection) { _addFsLevel(\%fs, \%cache, $$_[0], $$_[1]) };

    # if we've got any entries in %fs left, report them all as matches
    _lsFs(\%fs, $aref);
    $rv = 1;
  }
  pdebug("returning @{[ scalar @$aref ]} matches", 9);

  pOut();
  pdebug("leaving w/rv: $rv", 9);

  return $rv;
}

=head1 ptouch

  $rv = ptouch(\%errors, $epoch, @files);

Simulates the UNIX touch command.  Like the UNIX command this will create
zero-byte files if they don't exist.  The first argument is the timestamp to
apply to targets.  If undefined it will default to the current value of
time().

File arguments are processed through B<pglob> which allows you to use globs
to specify multiple existing files at once.  Don't use globbing to create 
multiple new files at once -- it won't work the way that you think it will.

The error message from each failed operation will be placed into the passed
hash ref using the filename as the key.

=cut

sub ptouch ($$@) {
  my $errRef  = shift;
  my $stamp   = shift;
  my @targets = @_;
  my $sarg    = defined $stamp ? $stamp : 'undef';
  my $rv      = 0;
  my ($fd, @ftargets, @tmp, $target);

  # Validate arguments
  croak "Invalid error hash reference passed to ptouch()" unless 
    defined $errRef && ref($errRef) eq 'HASH';
  croak "No targets passed to ptouch()" unless @targets;
  foreach (@targets) {
    croak "Undefined or zero-length arguments passed as file arguments " .
      "to ptouch()" unless defined $_ && length($_) > 0 };
  %$errRef = ();

  pdebug("entering w/($errRef)($sarg)(" . join(', ', 
    @targets) . ")", 9);
  pIn();

  # Apply the default timestamp if omitted
  $stamp = time() unless defined $stamp;

  # Expand file argument globs
  foreach (@targets) {
    $rv = pglob($_, \@tmp);
    last unless $rv;
    push(@ftargets, @tmp ? @tmp : $_);
  }

  # Touch the final targets
  if ($rv) {
    foreach $target (@ftargets) {
      pdebug("processing target $target", 10);
      $rv = 1;

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
      $rv = utime $stamp, $stamp, $target if $rv;
    }
  }

  if (scalar keys %$errRef) {
    Paranoid::ERROR = pdebug("errors occurred during processing",
      9);
    $rv = 0;
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

=cut

sub ptouchR ($$$@) {
  my $followLinks = shift;
  my $errRef      = shift;
  my $stamp       = shift;
  my @targets     = @_;

  # Validate arguments
  croak "Invalid error hash reference passed to ptouchR()" unless 
    defined $errRef && ref($errRef) eq 'HASH';
  croak "No targets passed to ptouchR()" unless @targets;
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
  croak "Undefined value passed to ptranslatePerms()" unless 
    defined $perm;

  pdebug("entering w/($perm)", 9);
  pIn();

  # Translate symbolic representation
  if ($perm =~ /^([ugo]+)([+\-])([rwxst]+)$/) {
    $o = $p = 00;
    @tmp = ($1, $2, $3);
    $o = 0700 if $tmp[0] =~ /u/;
    $o |= 0070 if $tmp[0] =~ /g/;
    $o |= 0007 if $tmp[0] =~ /o/;
    $p = 0444 if $tmp[2] =~ /r/;
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
  $p = 'undef' unless defined $p;

  pOut();
  pdebug("leaving w/rv: $p", 9);

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

sub pchmod ($@) {
  my $errRef  = shift;
  my $perms   = shift;
  my @targets = @_;
  my $rv      = 0;
  my ($ptrans, $target, $cperms, $addPerms, @ftargets, @tmp);

  # Validate arguments
  croak "Invalid error hash reference passed to ptouch()" unless 
    defined $errRef && ref($errRef) eq 'HASH';
  croak "Undefined permissions were passed to pchmod()" unless 
    defined $perms;
  croak "No targets passed to pchmod()" unless @targets;
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

  # Expand file argument globs
  foreach (@targets) {
    $rv = pglob($_, \@tmp);
    unless ($rv && @tmp) {
      Paranoid::ERROR = pdebug("non-existent file/glob " .
        "specified: $_", 9);
      $rv = 0;
      last;
    }
    push(@ftargets, @tmp);
  }

  # Apply permissions to final list of targets
  if ($rv) {

    foreach $target (@ftargets) {
      pdebug("processing target $target", 10);

      # If ptrans is defined we're going to do relative application
      # of permissions
      if (defined $ptrans) {

        # Get the current permissions
        $cperms = (stat $target)[2];
        $cperms = $addPerms ? $cperms | $ptrans : $cperms ^ $ptrans;
        $rv = chmod $cperms, $target;
        $$errRef{$target} = $! unless $rv;

      # Otherwise, the permissions are explicit
      } else {
        $rv = chmod $perms, $target;
        $$errRef{$target} = $! unless $rv;
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
  croak "Invalid error hash reference passed to pchmodR()" unless 
    defined $errRef && ref($errRef) eq 'HASH';
  croak "Undefined permissions were passed to pchmodR()" unless 
    defined $perms;
  croak "No targets passed to pchmodR()" unless @targets;
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
  my ($uuid, $ugid, @pwentry, @ftargets, @tmp, $target);

  # Validate arguments
  croak "Invalid error hash reference passed to pchown()" unless 
    defined $errRef && ref($errRef) eq 'HASH';
  croak "No user or group was passed to pchown()" unless defined $user ||
    defined $group;
  croak "No targets passed to pchown()" unless @targets;
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
    foreach (@targets) {
      $rv = pglob($_, \@tmp);
      unless ($rv && @tmp) {
        Paranoid::ERROR = pdebug("non-existent file/glob " .
          "specified: $_", 9);
        $rv = 0;
        last;
      }
      push(@ftargets, @tmp);
    }

    # Process the list
    foreach $target (@ftargets) {
      pdebug("processing target $target", 10);
      $rv = chown $user, $group, $target;
      $$errRef{$target} = $! unless $rv;
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
  croak "Invalid error hash reference passed to pchownR()" unless 
    defined $errRef && ref($errRef) eq 'HASH';
  croak "Undefined user and group were passed to pchownR()" unless 
    defined $user || defined $group;
  croak "No targets passed to pchownR()" unless @targets;
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

  # Validate args
  croak "Undefined value passed to pwhich()" unless defined $binary;

  pdebug("entering w/($binary)", 9);
  pIn();

  pdebug("PATH=$ENV{PATH}", 10);

  foreach (@directories) {
    pdebug("searching $_", 10);
    if (-r "$_/$binary" && -x _) {
      $match = "$_/$binary";
      $match =~ s#//#/#g;
      last;
    }
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

