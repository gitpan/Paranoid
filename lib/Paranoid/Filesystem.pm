# Paranoid::Filesystem -- Filesystem support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Filesystem.pm,v 0.16 2009/03/17 23:54:32 acorliss Exp $
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

package Paranoid::Filesystem;

use 5.006;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS);
use base qw(Exporter);
use File::Glob qw(bsd_glob);
use Paranoid;
use Paranoid::Debug qw(:all);
use Paranoid::Process qw(ptranslateUser ptranslateGroup);
use Paranoid::Input;
use Carp;
use Cwd qw(realpath);

($VERSION) = ( q$Revision: 0.16 $ =~ /(\d+(?:\.(\d+))+)/sm );

@EXPORT = qw(
    preadDir     psubdirs    pfiles    pglob
    pmkdir       prm         prmR      ptouch
    ptouchR      pchmod      pchmodR   pchown
    pchownR      pwhich
    );
@EXPORT_OK = qw(
    preadDir     psubdirs    pfiles    ptranslateLink
    pcleanPath   pglob       pmkdir    prm
    prmR         ptouch      ptouchR   ptranslatePerms
    pchmod       pchmodR     pchown    pchownR
    pwhich
    );
%EXPORT_TAGS = (
    all => [
        qw(preadDir     psubdirs    pfiles    ptranslateLink
            pcleanPath   pglob       pmkdir    prm
            prmR         ptouch      ptouchR   ptranslatePerms
            pchmod       pchmodR     pchown    pchownR
            pwhich)
           ],
);

use constant GLOBCHAR  => '\*\?\{\}\[\]';
use constant GLOBCHECK => '\*|\?|\{[^\}]*\}|\[[^\]]*\]';
use constant FNINVALID => '\'"\|\`\$';

#####################################################################
#
# Module code follows
#
#####################################################################

{
    my $maxlinks = 20;

    sub MAXLINKS : lvalue {

        # Purpose:  Gets/sets $maxlinks
        # Returns:  $maxlinks
        # Usage:    $max = MAXLINKS;
        # Usage:    MAXLINKS = 40;

        $maxlinks;
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

    # Purpose:  Generic wrapper for ptouch, prm, etc., to provide a
    #           recursive capability for all of them.  This also provides
    #           symlink filtering for all operations.
    # Returns:  True (1) for successful calls, False (0) for any errors
    # Usage:    $rv = _recurseWrapper($mode, $followLinks, \%errRef, @args);

    my $mode        = shift;
    my $followLinks = shift || 0;
    my $errRef      = shift;
    my @dargs       = @_;
    my $rv          = 1;
    my ( $op, $i, $o, @expanded );
    my ( @tmp, $target, @entries );
    my %subErrors;

    # Remove the timestamp from the args
    if ( $mode eq 'pchownR' ) {
        $op = [ splice @dargs, 0, 2 ];
    } elsif ( $mode ne 'prmR' ) {
        $op = shift @dargs;
    }
    $o = defined $op ? $op : 'undef';

    pdebug( "entering with ($mode)($followLinks)($errRef)($o)(@dargs)",
        PDLEVEL1 );
    pIn();

    # Expand all file arguments
    $rv = pglob( \%subErrors, \@expanded, @dargs );
    %$errRef = ( %$errRef, %subErrors );

    # Check for errors if this is ptouchR
    if ( $mode eq 'ptouchR' and scalar keys %subErrors ) {
        Paranoid::ERROR =
            pdebug( 'invalid glob matches in ptouchR mode', PDLEVEL2 );
        $rv = 0;
    }

    # Check error status so far
    if ($rv) {

        # Process glob list
        foreach $target (@expanded) {
            if (   ( $followLinks && -d $target )
                || ( -d $target && !-l $target ) ) {

                # Try to read the target directory
                if ( preadDir( $target, \@entries ) ) {

                    # Success! Call ourselves recursively on the entries
                    if (@entries) {
                        $rv = _recurseWrapper(
                            $mode,
                            $followLinks,
                            \%subErrors, (
                                  $mode eq 'pchownR' ? ( @$op, @entries )
                                : $mode ne 'prmR' ? ( $op, @entries )
                                : (@entries) ) );
                        %$errRef = ( %$errRef, %subErrors );
                    }
                } else {

                    # Failed to read the directory -- set the return value
                    $$errRef{$target} = "failed to read the directory: $!";
                    $rv = 0;
                }
            }
        }

        # If there's been no errors so far
        if ($rv) {

            # Filter out symlinks if requested
            @expanded = grep { !-l $_ } @expanded
                unless $followLinks
                    or $mode eq 'prmR';

            # Process list
            if (@expanded) {
                if ( $mode eq 'ptouchR' ) {
                    $rv = ptouch( \%subErrors, $op, @expanded );
                } elsif ( $mode eq 'prmR' ) {
                    $rv = prm( \%subErrors, @expanded );
                } elsif ( $mode eq 'pchmodR' ) {
                    $rv = pchmod( \%subErrors, $op, @expanded );
                } elsif ( $mode eq 'pchownR' ) {
                    $rv = pchown( \%subErrors, @$op, @expanded );
                } else {
                    Paranoid::ERROR =
                        pdebug( "called with unknown mode ($mode)",
                        PDLEVEL1 );
                    $rv = 0;
                }
            }
            %$errRef = ( %$errRef, %subErrors ) unless $rv;
        }
    }

    pOut();
    pdebug( "leaving in mode $mode w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub pmkdir ($;$) {

    # Purpose:  Simulates a 'mkdir -p' command in pure Perl
    # Returns:  True (1) if all targets were successfully created,
    #           False (0) if there are any errors
    # Usage:    $rv = pmkdir("/foo");
    # Usage:    $rv = pmkdir("/foo", 0750);

    my $path = shift;
    my $mode = shift;
    my $uarg = defined $mode ? $mode : 'undef';
    my $rv   = 1;
    my ( $dpath, @expanded, @elements, $testPath );

    # Validate arguments
    croak 'Mandatory first argument must be a defined path'
        unless defined $path && length $path;

    pdebug( "entering w/($path)($uarg)", PDLEVEL1 );
    pIn();

    # Set and detaint mode
    $mode = umask ^ 0777 unless defined $mode;
    unless ( detaint( $mode, 'number', \$mode ) ) {
        Paranoid::ERROR = pdebug( 'failed to detaint mode', PDLEVEL1 );
        pOut();
        pdebug( "leaving w/rv: $rv", PDLEVEL1 );
        return 0;
    }

    # Detaint input and filter through the shell glob
    if ( detaint( $path, 'fileglob', \$dpath ) ) {
        if ( @expanded = bsd_glob($dpath) ) {

            # Create all directories
            foreach (@expanded) {
                if ( -d $_ ) {
                    pdebug( "directory already exists: $_", PDLEVEL2 );
                } else {
                    $testPath = '';
                    @elements = split m#/+#sm, $_;
                    $elements[0] = '/' if $_ =~ m#^/#sm;
                    foreach (@elements) {
                        $testPath .= '/' if length $testPath;
                        $testPath .= $_;
                        unless ( -d $testPath ) {
                            if (detaint( $testPath, 'filename', \$testPath ) )
                            {
                                if ( mkdir $testPath, $mode ) {
                                    pdebug( "created $testPath", PDLEVEL2 );
                                } else {
                                    $rv = 0;
                                    Paranoid::ERROR = pdebug(
                                        "failed to create $testPath: $!",
                                        PDLEVEL2 );
                                    last;
                                }
                            } else {
                                Paranoid::ERROR = pdebug(
                                    'failed to detaint mkdir args: '
                                        . "$testPath $mode",
                                    PDLEVEL2
                                );
                                $rv = 0;
                                last;
                            }
                        }
                    }
                }
            }
        }
    } else {
        Paranoid::ERROR = pdebug( "failed to detaint: $path", PDLEVEL1 );
        $rv = 0;
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub prm ($@) {

    # Purpose:  Simulates a "rm -f" command in pure Perl
    # Returns:  True (1) if all targets were successfully removed,
    #           False (0) if there are any errors
    # Usage:    $rv = prm(\%errors, "/foo");

    my $errRef  = shift;
    my @targets = @_;
    my $rv      = 1;
    my ( @expanded, @tmp, $target );

    # Validate arguments
    croak 'Mandatory first argument must be a hash reference'
        unless defined $errRef && ref $errRef eq 'HASH';
    croak 'Mandatory remaining arguments must be present' unless @targets;
    foreach (@targets) {
        croak 'Undefined or zero-length arguments passed as file arguments'
            unless defined $_ && length $_ > 0;
    }
    %$errRef = ();

    pdebug( "entering w/($errRef)(" . join( ', ', @targets ) . ')',
        PDLEVEL1 );
    pIn();

    # Expand file argument globs
    $rv = pglob( $errRef, \@expanded, @targets );

    # Remove targets
    if ($rv) {
        foreach $target ( reverse sort @expanded ) {
            pdebug( "deleting target $target", PDLEVEL2 );

            # Is the directory there (and not a symlink)?
            if ( -d $target && !-l $target ) {

                # Yes it is -- kill it
                unless ( rmdir $target ) {

                    # Report our incompetence
                    Paranoid::ERROR =
                        pdebug( "Failed to delete $target: $!", PDLEVEL2 );
                    $$errRef{$target} = $!;
                    $rv = 0;
                }

            } elsif ( -e $target || -l $target ) {

                # No it isn't, so do a normal unlink
                unless ( unlink $target ) {

                    # Well, nice try, anyway...
                    Paranoid::ERROR =
                        pdebug( "Failed to delete $target: $!", PDLEVEL2 );
                    $$errRef{$target} = $!;
                    $rv = 0;
                }
            }
        }
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub prmR ($@) {

    # Purpose:  Recursively calls prm to simulate "rm -rf"
    # Returns:  True (1) if all targets were successfully removed,
    #           False (0) if there are any errors
    # Usage:    $rv = prmR(\%errors, "/foo");

    my $errRef  = shift;
    my @targets = @_;

    # Validate arguments
    croak 'Mandatory first argument must be a hash reference'
        unless defined $errRef && ref $errRef eq 'HASH';
    croak 'Mandatory remaining arguments must be present' unless @targets;
    foreach (@targets) {
        croak 'Undefined or zero-length arguments passed as file arguments'
            unless defined $_ && length $_ > 0;
    }
    %$errRef = ();

    return _recurseWrapper( 'prmR', 0, $errRef, @targets );
}

sub preadDir ($$;$) {

    # Purpose:  Populates the passed array ref with a list of all the
    #           directory entries (minus the '.' & '..') in the passed
    #           directory
    # Returns:  True (1) if the read was successful,
    #           False (0) if there are any errors
    # Usage:    $rv = preadDir("/tmp", \@entries);

    my $dir     = shift;
    my $aref    = shift;
    my $noLinks = shift || 0;
    my $rv      = 0;
    my ( $i, $fh );

    # Validate arguments
    croak 'Mandatory first argument must be a defined directory path'
        unless defined $dir;
    croak 'Mandatory second argument must be an array reference'
        unless defined $aref && ref $aref eq 'ARRAY';

    pdebug( "entering w/($dir)($aref)", PDLEVEL1 );
    pIn();
    @$aref = ();

    # Validate directory and exit early, if need be
    unless ( -e $dir && -d _ && -r _ ) {
        if ( !-e _ ) {
            Paranoid::ERROR =
                pdebug( "directory ($dir) does not exist", PDLEVEL1 );
        } elsif ( !-d _ ) {
            Paranoid::ERROR = pdebug( "$dir is not a directory", PDLEVEL1 );
        } else {
            Paranoid::ERROR = pdebug(
                "directory ($dir) is not readable by the effective user",
                PDLEVEL1 );
        }
        pOut();
        pdebug( "leaving w/rv: $rv", PDLEVEL1 );
        return $rv;
    }

    # Read the directory's contents
    if ( opendir $fh, $dir ) {

        # Get the list, filtering out '.' & '..'
        @$aref = grep !/^\.\.?$/sm, readdir $fh;
        closedir $fh;

        # Prepend the directory name to each entry
        foreach (@$aref) { $_ = "$dir/$_" }

        # Filter out symlinks, if necessary
        if ($noLinks) {
            $i = 0;
            while ( $i <= $#{$aref} ) {
                if ( -l $$aref[$i] ) {
                    splice @$aref, $i, 1;
                } else {
                    ++$i;
                }
            }
        }

        $rv = 1;
    } else {
        Paranoid::ERROR =
            pdebug( "error opening directory ($dir): $!", PDLEVEL1 );
    }
    pdebug( "returning @{[ scalar @$aref ]} entries", PDLEVEL1 );

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub psubdirs ($$;$) {

    # Purpose:  Performs a preadDir but filters out all non-directory entries
    #           so that only subdirectory entries are returned.  Can
    #           optionally filter out symlinks to directories as well.
    # Returns:  True (1) if the directory read was successful,
    #           False (0) if there are any errors
    # Usage:    $rv = psubdirs($dir, \@entries);
    # Usage:    $rv = psubdirs($dir, \@entries, 1);

    my $dir     = shift;
    my $aref    = shift;
    my $noLinks = shift || 0;
    my $rv      = 0;
    my @dirList;

    # Validate arguments
    croak 'Mandatory first argument must be a defined directory path'
        unless defined $dir;
    croak 'Mandatory second argument must be an array reference'
        unless defined $aref && ref $aref eq 'ARRAY';

    pdebug( "entering w/($dir)($aref)($noLinks)", PDLEVEL1 );
    pIn();

    # Empty target array and retrieve list
    @$aref = ();
    $rv = preadDir( $dir, \@dirList, $noLinks );

    # Filter out all non-directories
    foreach (@dirList) { push @$aref, $_ if -d $_ }
    pdebug( "returning @{[ scalar @$aref ]} entries", PDLEVEL1 );

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub pfiles ($$;$) {

    # Purpose:  Performs a preadDir but filters out all directory entries
    #           so that only file entries are returned.  Can
    #           optionally filter out symlinks to files as well.
    # Returns:  True (1) if the directory read was successful,
    #           False (0) if there are any errors
    # Usage:    $rv = psubdirs($dir, \@entries);
    # Usage:    $rv = psubdirs($dir, \@entries, 1);

    my $dir     = shift;
    my $aref    = shift;
    my $noLinks = shift;
    my $rv      = 0;
    my @fileList;

    # Validate arguments
    croak 'Mandatory first argument must be a defined directory path'
        unless defined $dir;
    croak 'Mandatory second argument must be an array reference'
        unless defined $aref && ref $aref eq 'ARRAY';

    pdebug( "entering w/($dir)($aref)", PDLEVEL1 );
    pIn();

    # Empty target array and retrieve list
    @$aref = ();
    $rv = preadDir( $dir, \@fileList, $noLinks );

    # Filter out all non-files
    foreach (@fileList) { push @$aref, $_ if -f $_ }
    pdebug( "returning @{[ scalar @$aref ]} entries", PDLEVEL1 );

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub pcleanPath ($) {

    # Purpose:  Removes/resolves directory artifacts like '/../', etc.
    # Returns:  Filtered string
    # Usage:    $filename = pcleanPath($filename);

    my $filename = shift;

    # Validate arguments
    croak 'Mandatory first argument must be a defined filename'
        unless defined $filename;

    pdebug( "entering w/($filename)", PDLEVEL1 );
    pIn();

    # Strip all //+, /./, and /{parent}/../
    while ( $filename =~ m#/\.?/+#sm ) { $filename =~ s#/\.?/+#/#smg }
    while ( $filename =~ m#/(?:(?!\.\.)[^/]{2,}|[^/])/\.\./#sm ) {
        $filename =~ s#/(?:(?!\.\.)[^/]{2,}|[^/])/\.\./#/#smg;
    }

    # Strip trailing /. and leading /../
    $filename =~ s#/\.$##sm;
    while ( $filename =~ m#^/\.\./#sm ) { $filename =~ s#^/\.\./#/#sm }

    # Strip any ^[^/]+/../
    while ( $filename =~ m#^[^/]+/\.\./#sm ) {
        $filename =~ s#^[^/]+/\.\./##sm;
    }

    # Strip any trailing /^[^/]+/..$
    while ( $filename =~ m#/[^/]+/\.\.$#sm ) {
        $filename =~ s#/[^/]+/\.\.$##sm;
    }

    pOut();
    pdebug( "leaving w/rv: $filename", PDLEVEL1 );

    return $filename;
}

sub ptranslateLink ($;$) {

    # Purpose:  Performs either a full (realpath) or a partial one (last
    #           filename element only) on the passed filename
    # Returns:  Altered filename if successful, undef if there are any
    #           failures
    # Usage:    $filename = ptranslateLink($filename);
    # Usage:    $filename = ptranslateLink($filename, 1);

    my $link           = shift;
    my $fullyTranslate = shift || 0;
    my $nLinks         = 0;
    my ( @elements, $i, $target );

    # Validate arguments
    croak 'Mandatory first argument must be a defined symlink filename'
        unless defined $link;

    pdebug( "entering w/($link)($fullyTranslate)", PDLEVEL1 );
    pIn();

    # Validate link and exit early, if need be
    unless ( -e $link ) {
        Paranoid::ERROR =
            pdebug( "link ($link) or target does not exist on filesystem",
            PDLEVEL1 );
        pOut();
        pdebug( 'leaving w/rv: undef', PDLEVEL1 );
        return undef;
    }

    # Check every element in the path for symlinks and translate it if
    # if a full translation was requested
    if ($fullyTranslate) {

        # Resolve the link
        $target = realpath($link);

        # Make sure we got an answer
        if ( defined $target ) {

            # Save the answer
            $link = $target;

        } else {

            # Report our inability to resolve the link
            Paranoid::ERROR =
                pdebug( "link ($link) couldn't be resolved fully: $!",
                PDLEVEL1 );
            $link = undef;
        }

    } else {

        # Is the file passed a symlink?
        if ( -l $link ) {

            # Yes it is, let's get the target
            $target = readlink $link;
            pdebug( "last element is a link to $target", PDLEVEL1 );

            # Is the target a relative filename?
            if ( $target =~ m#^(?:\.\.?/|[^/])#sm ) {

                # Yupper, replace the filename with the target
                $link =~ s#[^/]+$#$target#sm;

            } else {

                # The target is fully qualified, so replace link entirely
                $link = $target;
            }
        }
    }

    $link = pcleanPath($link) if defined $link;
    $target = defined $link ? $link : 'undef';

    pOut();
    pdebug( "leaving w/rv: $target", PDLEVEL1 );

    return $link;
}

sub pglob ($@) {

    # Purpose:  Acts similar to traditional BSD glob function except that it
    #           only returns a list of files that actually exist.
    # Returns:  True (1) if the glob successfully expanded,
    #           False (0) if there are any errors
    # Usage:    $rv = pglob(\%errors, \@targets, "/tmp/*");
    # Usage:    $rv = pglob("/tmp/*", \@targets);

    my @args = @_;
    my $rv   = 1;
    my ( $report, $glob, $href, $aref, @tmp, $f );

    # Validate arguments
    croak 'Mandatory first argument must be a defined glob or a '
        . 'hash reference'
        unless defined $args[0]
            and ( ref $args[0] eq 'HASH' or length $args[0] );

    # Detect which type of invocation was used
    if ( ref $args[0] eq 'HASH' ) {

        # New style invocation
        croak 'Mandatory second argument must be an array reference'
            unless ref $args[1] eq 'ARRAY';
        croak 'Mandatory third argument must be a defined file glob'
            unless defined $args[2];

        $href  = shift @args;
        $aref  = shift @args;
        %$href = ();

        $report = "($href)($aref)(@args)";
    } else {

        # Old-style invocation
        croak 'Mandatory first argument must be a defined file glob'
            unless defined $args[0];
        croak 'Mandatory second argument must be an array reference'
            unless ref $args[1] eq 'ARRAY';

        $glob = shift @args;
        $aref = shift @args;
        @args = ($glob);
        $href = {};

        $report = "($glob)($aref)";
    }
    @$aref = ();

    pdebug( "entering w/$report", PDLEVEL1 );
    pIn();

    # Process each glob
    foreach (@args) {

        # Did the glob detaint?
        if ( detaint( $_, 'fileglob', \$glob ) ) {

            # Yupper, so let's see if the string matches a literal file on
            # the filesystem
            if ( -l $glob or -e _ ) {

                # Yupper (part II), let's add it to the list
                push @$aref, $glob;

            } else {

                # Nope, so let's run it through the glob function for possible
                # expansion and see what gets returned
                @tmp = bsd_glob($glob);

                # Go through the shell glob results and test for the
                # existence of each file, pushing only those that exist
                # onto the array
                foreach $f (@tmp) {
                    if ( -l $f or -e _ ) {
                        push @$aref, $f;
                    } else {
                        $$href{$f} = 'file not found';
                    }
                }
                pdebug( "Matches from glob: @$aref", PDLEVEL2 );
            }
        } else {

            # The glob failed to detaint -- report it and error out
            Paranoid::ERROR =
                pdebug( "glob failed to detaint:  $_", PDLEVEL1 );
            $$href{$_} = 'glob failed to detaint';
            $rv = 0;
        }
    }

    pdebug( "returning @{[ scalar @$aref ]} matches", PDLEVEL1 );

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub ptouch ($$@) {

    # Purpose:  Simulates a "touch" command in pure Perl
    # Returns:  True (1) if all targets were successfully touched,
    #           False (0) if there are any errors
    # Usage:    $rv = ptouch(\%errors, $epoch, "/foo/*");

    my $errRef  = shift;
    my $stamp   = shift;
    my @targets = @_;
    my $sarg    = defined $stamp ? $stamp : 'undef';
    my $rv      = 1;
    my ( $fd, @expanded, $glob, @tmp, $target );

    # Validate arguments
    croak 'Mandatory first argument must be an array reference'
        unless defined $errRef && ref $errRef eq 'HASH';
    croak 'Mandatory remaining arguments must have at least one target'
        unless @targets;
    foreach (@targets) {
        croak 'Undefined or zero-length arguments passed as file arguments '
            . 'to ptouch()'
            unless defined $_ && length $_;
    }
    %$errRef = ();

    pdebug( "entering w/($errRef)($sarg)(" . join( ', ', @targets ) . ')',
        PDLEVEL1 );
    pIn();

    # Apply the default timestamp if omitted
    $stamp = time unless defined $stamp;

    # Detaint args and filter through the shell glob
    foreach (@targets) {
        if ( detaint( $_, 'fileglob', \$glob ) ) {
            if ( @tmp = bsd_glob($glob) ) {
                push @expanded, @tmp;
            }
        } else {
            Paranoid::ERROR = $$errRef{$_} =
                pdebug( "failed to detaint $_", PDLEVEL2 );
            $rv = 0;
        }
    }

    # Touch the final targets
    if ($rv) {
        foreach $target (@expanded) {
            pdebug( "processing target $target", PDLEVEL2 );

            # Detaint the filename
            if ( detaint( $target, 'filename', \$glob ) ) {

                # Filename detainted
                $target = $glob;

                # Create the target if it does not exist
                unless ( -e $target ) {
                    pdebug( "creating empty file ($target)", PDLEVEL2 );
                    if ( open $fd, '>>', $target ) {
                        close $fd;
                    } else {
                        $$errRef{$target} = $!;
                        $rv = 0;
                    }
                }

                # Touch the file
                if ( detaint( $stamp, 'number', \$glob ) ) {
                    $stamp = $glob;
                    $rv = utime $stamp, $stamp, $target if $rv;
                } else {
                    Paranoid::ERROR =
                        pdebug( "Invalid characters in timestamp: $stamp",
                        PDLEVEL2 );
                    $rv = 0;
                }
            } else {

                # Failed detainting
                Paranoid::ERROR = $$errRef{$target} =
                    pdebug( "Invalid characters in filename: $target",
                    PDLEVEL2 );
                $rv = 0;
            }
        }
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub ptouchR ($$$@) {

    # Purpose:  Calls ptouch recursively
    # Returns:  True (1) if all targets were successfully touched,
    #           False (0) if there are any errors
    # Usage:    $rv = ptouch(\%errors, $epoch, "/foo");

    my $followLinks = shift;
    my $errRef      = shift;
    my $stamp       = shift;
    my @targets     = @_;

    # Validate arguments
    croak 'Mandatory second argument must be a hash reference'
        unless defined $errRef && ref $errRef eq 'HASH';
    croak 'Mandatory remaing arguments must be at least one target'
        unless @targets;
    foreach (@targets) {
        croak 'Undefined or zero-length arguments passed as file arguments '
            . 'to ptouchR()'
            unless defined $_ && length $_ > 0;
    }
    %$errRef = ();

    return _recurseWrapper( 'ptouchR', $followLinks, $errRef, $stamp,
        @targets );
}

sub ptranslatePerms ($) {
    my $perm = shift;
    my $rv   = undef;
    my ( @tmp, $o, $p );

    # Validate arguments
    croak 'Mandatory first argument must be a defined permissions string'
        unless defined $perm;

    pdebug( "entering w/($perm)", PDLEVEL1 );
    pIn();

    # Validate permissions string
    if ( $perm =~ /^([ugo]+)([+\-])([rwxst]+)$/sm ) {

        # Translate symbolic representation
        $o = $p = 00;
        @tmp = ( $1, $2, $3 );
        $o = 0700 if $tmp[0] =~ /u/sm;
        $o |= 0070 if $tmp[0] =~ /g/sm;
        $o |= 0007 if $tmp[0] =~ /o/sm;
        $p = 0444 if $tmp[2] =~ /r/sm;
        $p |= 0222 if $tmp[2] =~ /w/sm;
        $p |= 0111 if $tmp[2] =~ /x/sm;
        $p &= $o;
        $p |= 01000 if $tmp[2] =~ /t/sm;
        $p |= 02000 if $tmp[2] =~ /s/sm && $tmp[0] =~ /g/sm;
        $p |= 04000 if $tmp[2] =~ /s/sm && $tmp[0] =~ /u/sm;

    } else {

        # Report invalid characters in permission string
        Paranoid::ERROR = pdebug( "invalid permissions ($perm)", PDLEVEL1 );
    }
    $rv = $p;

    pOut();
    pdebug( (
            defined $rv
            ? sprintf( 'leaving w/rv: %04o', $rv )
            : 'leaving w/rv: undef'
        ),
        PDLEVEL1
    );

    return $rv;
}

sub pchmod ($$@) {

    # Purpose:  Simulates a "chmod" command in pure Perl
    # Returns:  True (1) if all targets were successfully chmod'd,
    #           False (0) if there are any errors
    # Usage:    $rv = pchmod(\%errors, $perms, "/foo");

    my $errRef  = shift;
    my $perms   = shift;
    my @targets = @_;
    my $rv      = 0;
    my ( $ptrans, $target, $cperms, $addPerms, @expanded, @tmp );

    # Validate arguments
    croak 'Mandatory first argument must be a hash reference'
        unless defined $errRef && ref $errRef eq 'HASH';
    croak 'Mandatory second argument must a defined permissions string'
        unless defined $perms;
    croak 'Mandatory remaining arguments must have at least one target'
        unless @targets;
    foreach (@targets) {
        croak 'Undefined or zero-length arguments passed as file arguments '
            . 'to pchmod()'
            unless defined $_ && length $_ > 0;
    }
    %$errRef = ();

    pdebug( "entering w/($errRef)($perms)(" . join( ', ', @targets ) . ')',
        PDLEVEL1 );
    pIn();

    # Convert perms if they're symbolic
    $ptrans = ptranslatePerms($perms);
    if ( defined $ptrans ) {
        $addPerms = $perms =~ /-/sm ? 0 : 1;
    }

    # Expand file argument globs and check for mismatches
    $rv = pglob( $errRef, \@expanded, @targets );
    if ( scalar keys %$errRef ) {
        Paranoid::ERROR = pdebug( 'invalid glob matches', PDLEVEL2 );
        $rv = 0;
    }
    unless (@expanded) {
        Paranoid::ERROR = pdebug( 'no files found to chmod', PDLEVEL2 );
        $rv = 0;
    }

    if ($rv) {

        # Apply permissions to final list of targets
        foreach $target (@expanded) {
            pdebug( "processing target $target", PDLEVEL2 );

            # Skip non-existent targets
            unless ( -e $target ) {
                pdebug( "target missing: $target", PDLEVEL2 );
                $$errRef{$target} = 'file not found';
                next;
            }

            # Detaint target
            @tmp = ($target);
            unless ( detaint( $target, 'filename', \$target ) ) {
                pdebug( "failed to detaint target: $tmp[0]", PDLEVEL2 );
                $$errRef{$target} = 'couldn\'t detaint filename ';
                $rv = 0;
                next;
            }

            if ( defined $ptrans ) {

                # If ptrans is defined we're going to do relative
                # application of permissions
                pdebug(
                    $addPerms
                    ? sprintf( 'adding perms %04o',   $ptrans )
                    : sprintf( 'removing perms %04o', $ptrans ),
                    PDLEVEL2
                );

                # Get the current permissions
                $cperms = ( stat $target )[2] & 07777;
                pdebug(
                    sprintf(
                        'current permissions of $target: %04o', $cperms
                    ),
                    PDLEVEL2
                );
                $cperms =
                    $addPerms
                    ? ( $cperms | $ptrans )
                    : ( $cperms & ( 07777 ^ $ptrans ) );
                pdebug(
                    sprintf( 'new permissions of $target: %04o', $cperms ),
                    PDLEVEL2 );
                $rv = chmod $cperms, $target;
                $$errRef{$target} = $! unless $rv;

            } else {

                # Otherwise, the permissions are explicit
                #
                # Detaint number mode
                if ( detaint( $perms, 'number', \$perms ) ) {

                    # Detainted, now apply
                    pdebug( sprintf( 'changing to perms %04o', $perms ),
                        PDLEVEL2 );
                    $rv = chmod $perms, $target;
                    $$errRef{$target} = $! unless $rv;
                } else {

                    # Detainting failed -- report
                    Paranoid::ERROR = $$errRef{$target} =
                        pdebug( 'failed to detaint permissions mode',
                        PDLEVEL1 );
                    $rv = 0;
                }
            }
        }

        # Report the errors
        if ( scalar keys %$errRef ) {
            Paranoid::ERROR =
                pdebug( 'errors occured while applying permissions',
                PDLEVEL1 );
            $rv = 0;
        }
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub pchmodR ($$$@) {

    # Purpose:  Recursively calls pchmod
    # Returns:  True (1) if all targets were successfully chmod'd,
    #           False (0) if there are any errors
    # Usage:    $rv = pchmodR(\%errors, $perms, "/foo");

    my $followLinks = shift;
    my $errRef      = shift;
    my $perms       = shift;
    my @targets     = @_;
    my $rv          = 1;
    my @tmp;

    # Validate arguments
    croak 'Mandatory second argument must be an array reference'
        unless defined $errRef && ref $errRef eq 'HASH';
    croak 'Mandatory third argument must be a defined permissions string'
        unless defined $perms;
    croak 'Mandatory remaining arguments must be a least one target'
        unless @targets;
    foreach (@targets) {
        croak 'Undefined or zero-length arguments passed as file arguments '
            . 'to pchmodR()'
            unless defined $_ && length $_ > 0;
    }
    %$errRef = ();

    # Make sure we've got some targets to start with
    if ( pglob( $errRef, \@tmp, @targets ) ) {
        unless (@tmp) {
            Paranoid::ERROR = pdebug( 'no files to chmod', PDLEVEL1 );
            $rv = 0;
        }
    }

    $rv =
        _recurseWrapper( 'pchmodR', $followLinks, $errRef, $perms, @targets )
        if $rv;

    return $rv;
}

sub pchown ($$$@) {

    # Purpose:  Simulates a "chown" command in pure Perl
    # Returns:  True (1) if all targets were successfully owned,
    #           False (0) if there are any errors
    # Usage:    $rv = pchown(\%errors, $user, $group, "/foo");

    my $errRef  = shift;
    my $user    = shift;
    my $group   = shift;
    my @targets = @_;
    my $rv      = 0;
    my ( @expanded, @tmp, $target, $t );

    # Validate arguments
    croak 'Mandatory first argument must be a hash reference'
        unless defined $errRef && ref $errRef eq 'HASH';
    croak 'Mandatory second or third argument must be a defined user or '
        . 'group'
        unless defined $user || defined $group;
    croak 'Mandatory remaining arguments must be at least one target'
        unless @targets;
    foreach (@targets) {
        croak 'Undefined or zero-length arguments passed as file arguments '
            . 'to pchown()'
            unless defined $_ && length $_ > 0;
    }
    %$errRef = ();

    $user  = -1 unless defined $user;
    $group = -1 unless defined $group;

    pdebug(
        "entering w/($errRef)($user)($group)(" . join( ', ', @targets ) . ')',
        PDLEVEL1
    );
    pIn();

    # Translate to UID
    $user = ptranslateUser($user) unless $user =~ /^-?\d+$/sm;

    # Translate to GID
    $group = ptranslateGroup($group) unless $group =~ /^-?\d+$/sm;

    # Have we translated both successfully?
    if ( defined $user && defined $group ) {

        # Proceed
        pdebug( "UID: $user GID: $group", PDLEVEL2 );

        # Expand file argument globs
        $rv = pglob( $errRef, \@expanded, @targets );
        if ( scalar keys %$errRef ) {
            Paranoid::ERROR = pdebug( 'invalid glob matches', PDLEVEL2 );
            $rv = 0;
        }

        # Process the list
        foreach $target (@expanded) {
            $t = $target;
            if ( detaint( $target, 'filename', \$target ) ) {
                pdebug( "processing target $target", PDLEVEL2 );
                $rv = chown $user, $group, $target;
                $$errRef{$target} = $! unless $rv;
            } else {
                $$errRef{$t} = 'error detainting directory' unless $rv;
                $rv = 0;
            }
        }

        # Report the errors
        if ( scalar keys %$errRef ) {
            Paranoid::ERROR =
                pdebug( 'errors occured while applying ownership', PDLEVEL1 );
            $rv = 0;
        }

    } else {

        # Failed to translate ids -- report
        Paranoid::ERROR =
            pdebug( 'unsuccessful at translating uid/gid', PDLEVEL1 );
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub pchownR ($$$$@) {

    # Purpose:  Calls pchown recursively
    # Returns:  True (1) if all targets were successfully owned,
    #           False (0) if there are any errors
    # Usage:    $rv = pchownR(\%errors, $user, $group, "/foo");

    my $followLinks = shift;
    my $errRef      = shift;
    my $user        = shift;
    my $group       = shift;
    my $rv          = 1;
    my @targets     = @_;
    my @tmp;

    # Validate arguments
    croak 'Mandatory second argument must be a hash reference'
        unless defined $errRef && ref $errRef eq 'HASH';
    croak 'Mandatory third or fourth argument must be a defined user or '
        . 'group'
        unless defined $user || defined $group;
    croak 'Mandatory remaining arguments must be at least one target'
        unless @targets;
    foreach (@targets) {
        croak 'Undefined or zero-length arguments passed as file arguments '
            . 'to pchownR()'
            unless defined $_ && length $_ > 0;
    }
    %$errRef = ();

    # Make sure we've got some targets to start with
    if ( pglob( $errRef, \@tmp, @targets ) ) {
        unless (@tmp) {
            Paranoid::ERROR = pdebug( 'no files to chmod', PDLEVEL1 );
            $rv = 0;
        }
    }

    $rv =
        _recurseWrapper( 'pchownR', $followLinks, $errRef, $user, $group,
        @targets )
        if $rv;

    return $rv;
}

sub pwhich ($) {

    # Purpose:  Simulates a "which" command in pure Perl
    # Returns:  The full path to the requested program if successful
    #           undef if not found
    # Usage:    $filename = pwhich('ls');

    my $binary      = shift;
    my @directories = grep /^.+$/sm, split /:/sm, $ENV{PATH};
    my $match       = undef;
    my $b;

    # Validate args
    croak 'Mandatory first argument must be a defined binary name'
        unless defined $binary;

    pdebug( "entering w/($binary)", PDLEVEL1 );
    pIn();

    # Try to detaint filename
    if ( detaint( $binary, 'filename', \$b ) ) {

        # Success -- start searching directories in PATH
        foreach (@directories) {
            pdebug( "searching $_", PDLEVEL2 );
            if ( -r "$_/$b" && -x _ ) {
                $match = "$_/$b";
                $match =~ s#/+#/#smg;
                last;
            }
        }

    } else {

        # Report detaint failure
        Paranoid::ERROR = pdebug( "failed to detaint $binary", PDLEVEL1 );
    }

    pOut();
    pdebug( 'leaving w/rv: ' . ( defined $match ? $match : 'undef' ),
        PDLEVEL1 );

    return $match;
}

1;

__END__

=head1 NAME

Paranoid::Filesystem - Filesystem Functions

=head1 VERSION

$Id: Filesystem.pm,v 0.16 2009/03/17 23:54:32 acorliss Exp $

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

=head1 DESCRIPTION

This module provides a few functions to make accessing the filesystem a little
easier, while instituting some safety checks.  If you want to enable debug
tracing into each function you must set B<PDEBUG> to at least 9.

B<pcleanPath>, B<ptranslateLink>, and B<ptranslatePerms> are only exported 
if this module is used with the B<:all> target.

B<NOTE:> All of these functions detaint all filename, directory, and glob
arguments using B<detaint> from B<Paranoid::Input>.  If you find the default 
I<filename> or I<fileglob> regexes to be too strict (and they are certainly
more strict than what filesystems actually support) you will have to redefine
them using B<addTaintRegex>.

=head1 SUBROUTINES/METHODS

=head2 MAXLINKS

  Paranoid::Filesystem::MAXLINKS = 20;

This lvalue subroutine sets the maximum number of symlinks that will be 
tolerated in a filename for translation purposes.  This prevents a runaway 
process due to circular references between symlinks.

=head2 pmkdir

  $rv = pmkdir("/foo", 0750);

This function simulates a 'mkdir -p {path}', returning false if it fails for
any reason other than the directory already being present.  The second
argument (permissions) is optional, but if present should be an octal number.
Shell-style globs are supported as the path argument.

=head2 prm

  $rv = prm(\%errors, "/foo", "/bar/*");

This function unlinks non-directories and rmdir's directories.  File 
arguments are processed through B<pglob> and expanded into multiple
targets if globs are detected.

The error message from each failed operation will be placed into the passed
hash ref using the filename as the key.

B<NOTE>:  If you ask it to delete something that's not there it will silently
succeed.

=head2 prmR

  $rv = prmR(\%errors, "/foo/*");

This function works the same as B<prm> but performs a recursive delete,
similar to "rm -r" on the command line.

=head2 preadDir

  $rv = preadDir("/etc", \@dirList);

This function populates the passed array with the contents of the specified
directory.  If there are any problems reading the directory the return value
will be false and a string explaining the error will be stored in
B<Paranoid::ERROR>.

All entries in the returned list will be prefixed with the directory name.  An
optional third boolean argument can be given to filter out symlinks from the
results.

=head2 psubdirs

  $rv = psubdirs("/etc", \@dirList);

This function calls B<preadDir> in the background and filters the list for
directory (or symlinks to) entries.  It also returns a true if the command was
processed with no problems, and false otherwise.

Like B<preadDir> an optional third boolean argument can be passed that causes
symlinks to be filtered out.

=head2 pfiles

  $rv = pfiles("/etc", \@filesList);

This function calls B<preadDir> in the background and filters the list for
file (or symlinks to) entries.  It also returns a true if the command was
processed with no problems, and false otherwise.

Like B<preadDir> an optional third boolean argument can be passed that causes
symlinks to be filtered out.

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

=head2 ptouch

  $rv = ptouch(\%errors, $epoch, @files);

Simulates the UNIX touch command.  Like the UNIX command this will create
zero-byte files if they don't exist.  The first argument is the timestamp to
apply to targets.  If undefined it will default to the current value of
time().

Shell-style globs are supported.

The error message from each failed operation will be placed into the passed
hash ref using the filename as the key.

=head2 ptouchR

  $rv = ptouchR(1, \%errors, $epoch, @files);

This function works the same as B<ptouch>, but requires one additional
argument (the first argument), boolean, which indicates whether or not the
command should follow symlinks.

You cannot use this function to create new, non-existant files, this only
works to update an existing directory heirarchy's mtime.

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

=head2 pchmodR

  $rv = pchmodR(1, \%errors, $perms, @files);

This function works the same as B<pchmod>, but requires one additional
argument (the first argument), boolean, which indicates whether or not the
command should follow symlinks.

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

=head2 pchownR

  $rv = pchownR(1, \%errors, $user, $group, @files);

This function works the same as B<pchown>, but requires one additional
argument (the first argument), boolean, which indicates whether or not the
command should follow symlinks.

=head2 pwhich

  $fullname = pwhich('ls');

This function tests each directory in your path for a binary that's both
readable and executable by the effective user.  It will return only one
match, stopping the search on the first match.  If no matches are found it
will return undef.

=head1 DEPENDENCIES

=over

=item o

L<Cwd>

=item o

L<File::Glob>

=item o

L<Paranoid>

=item o

L<Paranoid::Debug>

=item o

L<Paranoid::Input>

=back

=head1 BUGS AND LIMITATIONS

B<ptranslateLink> is probably pointless for 99% of the uses out there, you're
better off using B<Cwd>'s B<realpath> function instead.  The only thing it can
do differently is translating a single link itself, without translating any
additional symlinks found in the preceding path.  But, again, you probably
won't want that in most circumstances.

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

