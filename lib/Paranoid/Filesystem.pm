# Paranoid::Filesystem -- Filesystem support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Filesystem.pm,v 0.19 2010/06/03 19:01:11 acorliss Exp $
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
use Carp;
use Cwd qw(realpath);
use Errno qw(:POSIX);
use Fcntl qw(:mode);
use Paranoid;
use Paranoid::Debug qw(:all);
use Paranoid::Process qw(ptranslateUser ptranslateGroup);
use Paranoid::Input;
use Paranoid::Glob;

($VERSION) = ( q$Revision: 0.19 $ =~ /(\d+(?:\.(\d+))+)/sm );

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

use constant PERMMASK => 07777;

#####################################################################
#
# Module code follows
#
#####################################################################

sub pmkdir ($;$) {

    # Purpose:  Simulates a 'mkdir -p' command in pure Perl
    # Returns:  True (1) if all targets were successfully created,
    #           False (0) if there are any errors
    # Usage:    $rv = pmkdir("/foo/{a1,b2}");
    # Usage:    $rv = pmkdir("/foo", 0750);

    my ( $path, $mode ) = @_;
    my ( $dirs, $directory, @parts, $i );
    my $uarg = defined $mode ? $mode : 'undef';
    my $rv = 1;

    # Validate arguments
    unless ( defined $path && length $path ) {
        Paranoid::ERROR =
            pdebug( 'Mandatory first argument must be a defined path',
            PDLEVEL1 );
        return 0;
    }

    pdebug( "entering w/($path)($uarg)", PDLEVEL1 );
    pIn();

    # Create a glob object if we weren't handed one.
    $dirs =
        ref $path eq 'Paranoid::Glob'
        ? $path
        : Paranoid::Glob->new( globs => [$path] );

    # Leave Paranoid::Glob's errors in place if there was a problem
    $rv = 0 unless defined $dirs;

    # Set and detaint mode
    if ($rv) {
        $mode = umask ^ PERMMASK unless defined $mode;
        unless ( detaint( $mode, 'number', \$mode ) ) {
            Paranoid::ERROR =
                pdebug( 'invalid mode argument passed', PDLEVEL1 );
            $rv = 0;
        }
    }

    # Start creating directories
    if ($rv) {

        # Iterate over each directory in the glob
        PMKDIR: foreach $directory (@$dirs) {
            pdebug( "processing $directory", PDLEVEL2 );

            # Skip directories already present
            next if -d $directory;

            # Otherwise, split so we can backtrack to the first available
            # subdirectory and start creating subdirectories from there
            @parts = split m#/+#sm, $directory;
            $i = $parts[0] eq '' ? 1 : 0;
            $i++ while $i < $#parts and -d join '/', @parts[ 0 .. $i ];
            while ( $i <= $#parts ) {
                unless ( mkdir join( '/', @parts[ 0 .. $i ] ), $mode ) {

                    # Error out and halt all work
                    Paranoid::ERROR =
                        pdebug( "failed to create $directory: $!", PDLEVEL1 );
                    $rv = 0;
                    last PMKDIR;
                }
                $i++;
            }
        }
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub prm (@) {

    # Purpose:  Simulates a "rm -f" command in pure Perl
    # Returns:  True (1) if all targets were successfully removed,
    #           False (0) if there are any errors
    # Usage:    $rv = prm(\%errors, "/foo");

    my $errRef  = shift;
    my @targets = grep {defined} splice @_;
    my $rv      = 1;
    my ( $glob, $tglob, @fstat );

    # Validate arguments
    croak 'Mandatory first argument must be a hash reference'
        unless defined $errRef && ref $errRef eq 'HASH';
    %$errRef = ();

    pdebug( "entering w/(@targets)", PDLEVEL1 );
    pIn();

    # Create a glob object for interal use
    $glob = new Paranoid::Glob;

    # Add the contents of all the passed globs/strings
    foreach (@targets) {

        # Make sure we're dealing with globs
        $tglob =
            ref $_ eq 'Paranoid::Glob'
            ? $_
            : Paranoid::Glob->new( globs => [$_] );

        unless ( defined $tglob ) {

            # Error out
            $rv = 0;
            last;
        }

        # Add the contents of the temporary glob
        push @$glob, @$tglob;
    }

    # Start removing files
    if ($rv) {

        # Consolidate the entries
        $glob->consolidate;

        # Iterate over entries
        foreach ( reverse @$glob ) {
            pdebug( "processing $_", PDLEVEL2 );

            # Stat the file
            @fstat = lstat $_;

            # If the file is missing, consider the removal successful and
            # move on.
            next if $! == ENOENT;
            unless (@fstat) {

                # Report remaining errors (permission denied, etc.)
                $rv = 0;
                $$errRef{$_} = $!;
                pdebug( "failed to remove $_: $!", PDLEVEL1 );
                next;
            }

            if ( S_ISDIR( $fstat[2] ) ) {

                # Remove directories
                unless ( rmdir $_ ) {

                    # Record errors
                    $rv = 0;
                    $$errRef{$_} = $!;
                    pdebug( "failed to remove $_: $!", PDLEVEL1 );
                }

            } else {

                # Remove all non-directories
                unless ( unlink $_ ) {

                    # Record errors
                    $rv = 0;
                    $$errRef{$_} = $!;
                    pdebug( "failed to remove $_: $!", PDLEVEL1 );
                }
            }
        }
    }

    Paranoid::ERROR = pdebug( "Failed to delete targets", PDLEVEL1 )
        unless $rv;

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
    my @targets = grep {defined} splice @_;
    my $rv      = 1;
    my ( $glob, $tglob );

    pdebug( 'entering', PDLEVEL1 );
    pIn();

    # Create a glob object for interal use
    $glob = new Paranoid::Glob;

    # Add the contents of all the passed globs/strings
    foreach (@targets) {

        # Make sure we're dealing with globs
        $tglob =
            ref $_ eq 'Paranoid::Glob'
            ? $_
            : Paranoid::Glob->new( globs => [$_] );

        unless ( defined $tglob ) {

            # Error out
            $rv = 0;
            last;
        }

        # Add the contents of the temporary glob
        push @$glob, @$tglob;
    }

    if ($rv) {

        # Load the directory tree and execute prm
        $rv = $glob->recurse( 0, 1 ) && prm( $errRef, $glob );
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub preadDir ($$;$) {

    # Purpose:  Populates the passed array ref with a list of all the
    #           directory entries (minus the '.' & '..') in the passed
    #           directory
    # Returns:  True (1) if the read was successful,
    #           False (0) if there are any errors
    # Usage:    $rv = preadDir("/tmp", \@entries);

    my ( $dir, $aref, $noLinks ) = @_;
    my $adir = defined $dir ? $dir : 'undef';
    my $rv = 1;
    my $fh;

    # Validate arguments
    croak 'Mandatory second argument must be an array reference'
        unless defined $aref && ref $aref eq 'ARRAY';
    $noLinks = 0 unless defined $noLinks;

    pdebug( "entering w/($adir)($aref)($noLinks)", PDLEVEL1 );
    pIn();
    @$aref = ();

    # Validate directory and exit early, if need be
    unless ( defined $dir and -e $dir and -d _ and -r _ ) {
        $rv = 0;
        Paranoid::ERROR = pdebug( (
                  !defined $dir ? "undefined value passed as directory name"
                : !-e _         ? "directory ($dir) does not exist"
                : !-d _         ? "$dir is not a directory"
                : "directory ($dir) is not readable by the effective user"
            ),
            PDLEVEL1
            );
    }

    if ($rv) {

        # Read the directory's contents
        $rv = opendir $fh, $dir;

        if ($rv) {

            # Get the list, filtering out '.' & '..'
            foreach ( readdir $fh ) {
                push @$aref, "$dir/$_" unless m/^\.\.?$/sm;
            }
            closedir $fh;

            # Filter out symlinks, if necessary
            @$aref = grep { !-l $_ } @$aref if $noLinks;

        } else {
            Paranoid::ERROR =
                pdebug( "error opening directory ($dir): $!", PDLEVEL1 );
        }
    }

    pdebug( "returning @{[ scalar @$aref ]} entries", PDLEVEL2 );

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

    my ( $dir, $aref, $noLinks ) = @_;
    my $adir = defined $dir ? $dir : 'undef';
    my $rv = 0;

    # Validate arguments
    croak 'Mandatory second argument must be an array reference'
        unless defined $aref && ref $aref eq 'ARRAY';
    $noLinks = 0 unless defined $noLinks;

    pdebug( "entering w/($adir)($aref)($noLinks)", PDLEVEL1 );
    pIn();

    # Empty target array and retrieve list
    $rv = preadDir( $dir, $aref, $noLinks );

    # Filter out all non-directories
    @$aref = grep { -d $_ } @$aref if $rv;

    pdebug( "returning @{[ scalar @$aref ]} entries", PDLEVEL2 );

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
    # Usage:    $rv = pfiles($dir, \@entries);
    # Usage:    $rv = pfiles($dir, \@entries, 1);

    my ( $dir, $aref, $noLinks ) = @_;
    my $adir = defined $dir ? $dir : 'undef';
    my $rv = 0;

    # Validate arguments
    croak 'Mandatory second argument must be an array reference'
        unless defined $aref && ref $aref eq 'ARRAY';
    $noLinks = 0 unless defined $noLinks;

    pdebug( "entering w/($dir)($aref)", PDLEVEL1 );
    pIn();

    # Empty target array and retrieve list
    @$aref = ();
    $rv = preadDir( $dir, $aref, $noLinks );

    # Filter out all non-files
    @$aref = grep { -f $_ } @$aref if $rv;

    pdebug( "returning @{[ scalar @$aref ]} entries", PDLEVEL2 );

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
    my $l              = defined $link ? $link : 'undef';
    my ( $i, $target );

    pdebug( "entering w/($l)($fullyTranslate)", PDLEVEL1 );
    pIn();

    # Validate link and exit early, if need be
    unless ( defined $link and scalar lstat $link ) {
        Paranoid::ERROR =
            pdebug( "link ($l) does not exist on filesystem", PDLEVEL1 );
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
    my $glob = new Paranoid::Glob;
    my ( $report, $href, $aref );

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

        $href  = shift @args;
        $aref  = shift @args;
        %$href = ();

        $report = "($href)($aref)(@args)";
    } else {

        # Old-style invocation
        croak 'Mandatory second argument must be an array reference'
            unless ref $args[1] eq 'ARRAY';

        $aref = $args[1];
        splice @args, 1;
        $href = {};

        $report = "(@args)($aref)";
    }
    @$aref = ();
    @args = grep {defined} @args;

    pdebug( "entering w/$report", PDLEVEL1 );
    pIn();

    # Process each glob(s)
    if ( $glob->addGlobs(@args) ) {

        # All globs successfully detainted
        $glob->consolidate;
        @$aref = $glob->exists;

    } else {
        @$aref = ();
        $rv    = 0;
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

    my ( $errRef, $stamp ) = splice @_, 0, 2;
    my @targets = grep {defined} splice @_;
    my $sarg = defined $stamp ? $stamp : 'undef';
    my $glob = new Paranoid::Glob;
    my $rv   = 1;
    my $irv  = 1;
    my ( $tglob, $fh, $target );

    # Validate arguments
    croak 'Mandatory first argument must be a hash reference'
        unless defined $errRef && ref $errRef eq 'HASH';
    %$errRef = ();

    pdebug(
        "entering w/($errRef)($sarg)"
            . "(@{[ join ',', map { defined $_ ? $_ : 'undef' } @targets ]})",
        PDLEVEL1
        );
    pIn();

    # Apply the default timestamp if omitted
    $stamp = time unless defined $stamp;

    # Add the contents of all the passed globs/strings
    foreach (@targets) {

        # Make sure we're dealing with globs
        $tglob =
            ref $_ eq 'Paranoid::Glob'
            ? $_
            : Paranoid::Glob->new( globs => [$_] );

        unless ( defined $tglob ) {

            # Error out
            $rv = 0;
            last;
        }

        # Add the contents of the temporary glob
        push @$glob, @$tglob;
    }

    if ($rv) {
        unless ( detaint( $stamp, 'number', \$sarg ) ) {
            Paranoid::ERROR =
                pdebug( "Invalid characters in timestamp: $stamp", PDLEVEL2 );
            $rv = 0;
        }
    }

    # Start touching stuff
    if ($rv) {

        # Copy over the detainted stamp value
        $stamp = $sarg;

        # Consolidate the entries
        $glob->consolidate;

        # Iterate over entries
        foreach $target (@$glob) {
            pdebug( "processing $target", PDLEVEL2 );
            $irv = 1;

            # Create the target if it does not exist
            unless ( -e $target ) {
                pdebug( "creating empty file ($target)", PDLEVEL2 );
                if ( open $fh, '>>', $target ) {
                    close $fh;
                } else {
                    $$errRef{$target} = $!;
                    $irv = $rv = 0;
                }
            }

            # Touch the file
            if ($irv) {
                unless ( utime $stamp, $stamp, $target ) {
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

sub ptouchR ($$$@) {

    # Purpose:  Calls ptouch recursively
    # Returns:  True (1) if all targets were successfully touched,
    #           False (0) if there are any errors
    # Usage:    $rv = ptouchR(1, \%errors, $epoch, "/foo");

    my ( $follow, $errRef, $epoch ) = splice @_, 0, 3;
    my @targets = grep {defined} splice @_;
    my $rv = 1;
    my ( $glob, $tglob );

    pdebug( 'entering', PDLEVEL1 );
    pIn();

    # Create a glob object for interal use
    $glob = new Paranoid::Glob;

    # Add the contents of all the passed globs/strings
    foreach (@targets) {

        # Make sure we're dealing with globs
        $tglob =
            ref $_ eq 'Paranoid::Glob'
            ? $_
            : Paranoid::Glob->new( globs => [$_] );

        unless ( defined $tglob ) {

            # Error out
            $rv = 0;
            last;
        }

        # Add the contents of the temporary glob
        push @$glob, @$tglob;
    }

    if ($rv) {

        # Load the directory tree and execute prm
        $rv =
            $glob->recurse( $follow, 1 ) && ptouch( $errRef, $epoch, $glob );
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub ptranslatePerms ($) {

    # Purpose:  Translates symbolic permissions (as supported by userland
    #           chmod, etc.) into the octal permissions.
    # Returns:  Numeric permissions if valid symbolic permissions were passed,
    #           undef otherwise
    # Usage:    $perm = ptranslatePerms('ug+srw');

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
        $o = S_IRWXU if $tmp[0] =~ /u/sm;
        $o |= S_IRWXG if $tmp[0] =~ /g/sm;
        $o |= S_IRWXO if $tmp[0] =~ /o/sm;
        $p = ( S_IRUSR | S_IRGRP | S_IROTH ) if $tmp[2] =~ /r/sm;
        $p |= ( S_IWUSR | S_IWGRP | S_IWOTH ) if $tmp[2] =~ /w/sm;
        $p |= ( S_IXUSR | S_IXGRP | S_IXOTH ) if $tmp[2] =~ /x/sm;
        $p &= $o;
        $p |= S_ISVTX if $tmp[2] =~ /t/sm;
        $p |= S_ISGID if $tmp[2] =~ /s/sm && $tmp[0] =~ /g/sm;
        $p |= S_ISUID if $tmp[2] =~ /s/sm && $tmp[0] =~ /u/sm;

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

    my ( $errRef, $perms ) = splice @_, 0, 2;
    my @targets = grep {defined} splice @_;
    my $rv = 1;
    my ( $glob, $tglob, @fstat );
    my ( $ptrans, $target, $cperms, $addPerms, @tmp );

    # Validate arguments
    croak 'Mandatory first argument must be a hash reference'
        unless defined $errRef && ref $errRef eq 'HASH';
    croak 'Mandatory second argument must a defined permissions string'
        unless defined $perms;
    %$errRef = ();

    pdebug(
        "entering w/($errRef)($perms)("
            . "(@{[ join ',', map { defined $_ ? $_ : 'undef' } @targets ]})",
        PDLEVEL1
        );
    pIn();

    # Convert perms if they're symbolic
    $ptrans = ptranslatePerms($perms);
    if ( defined $ptrans ) {
        $addPerms = $perms =~ /-/sm ? 0 : 1;
    }

    # Add the contents of all the passed globs/strings
    $glob = new Paranoid::Glob;
    foreach (@targets) {

        # Make sure we're dealing with globs
        $tglob =
            ref $_ eq 'Paranoid::Glob'
            ? $_
            : Paranoid::Glob->new( globs => [$_] );

        unless ( defined $tglob ) {

            # Error out
            Paranoid::ERROR = pdebug( "failed to glob $_", PDLEVEL1 );
            $rv = 0;
            last;
        }

        # Add the contents of the temporary glob
        push @$glob, @$tglob;
    }

    if ($rv) {

        # Consolidate the entries
        $glob->consolidate;

        # Iterate over entries
        foreach (@$glob) {
            pdebug( "processing $_", PDLEVEL2 );

            if ( defined $ptrans ) {

                # Get the current file mode
                @fstat = stat $_;
                unless (@fstat) {
                    $rv = 0;
                    $$errRef{$_} = $!;
                    Paranoid::ERROR =
                        pdebug( "failed to adjust permissions of $_: $!",
                        PDLEVEL1 );
                    next;
                }

                # If ptrans is defined we're going to do relative
                # application of permissions
                pdebug(
                    $addPerms
                    ? sprintf( 'adding perms %04o',   $ptrans )
                    : sprintf( 'removing perms %04o', $ptrans ),
                    PDLEVEL2
                    );

                # Get the current permissions
                $cperms = $fstat[2] & PERMMASK;
                pdebug(
                    sprintf( 'current permissions of %s: %04o', $_, $cperms ),
                    PDLEVEL2
                    );
                $cperms =
                    $addPerms
                    ? ( $cperms | $ptrans )
                    : ( $cperms & ( PERMMASK ^ $ptrans ) );
                pdebug( sprintf( 'new permissions of %s: %04o', $_, $cperms ),
                    PDLEVEL2 );
                unless ( chmod $cperms, $_ ) {
                    $rv = 0;
                    $$errRef{$_} = $!;
                    Paranoid::ERROR =
                        pdebug( "failed to adjust permissions of $_: $!",
                        PDLEVEL1 );
                }

            } else {

                # Otherwise, the permissions are explicit
                #
                # Detaint number mode
                if ( detaint( $perms, 'number', \$perms ) ) {

                    # Detainted, now apply
                    pdebug(
                        sprintf(
                            'assigning permissions of %04o to %s',
                            $perms, $_
                            ),
                        PDLEVEL2
                        );
                    unless ( chmod $perms, $_ ) {
                        $rv = 0;
                        $$errRef{$_} = $!;
                    }
                } else {

                    # Detainting failed -- report
                    $$errRef{$_} = $!;
                    Paranoid::ERROR =
                        pdebug( 'failed to detaint permissions mode',
                        PDLEVEL1 );
                    $rv = 0;
                }
            }
        }

        # Report the errors
        Paranoid::ERROR =
            pdebug( 'errors occured while applying permissions', PDLEVEL1 )
            unless $rv;
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub pchmodR ($$$@) {

    # Purpose:  Recursively calls pchmod
    # Returns:  True (1) if all targets were successfully chmod'd,
    #           False (0) if there are any errors
    # Usage:    $rv = pchmodR(0, \%errors, $perms, "/foo");

    my ( $follow, $errRef, $perms ) = splice @_, 0, 3;
    my @targets = grep {defined} splice @_;
    my $rv = 1;
    my ( $glob, $tglob );

    pdebug( 'entering', PDLEVEL1 );
    pIn();

    # Create a glob object for interal use
    $glob = new Paranoid::Glob;

    # Add the contents of all the passed globs/strings
    foreach (@targets) {

        # Make sure we're dealing with globs
        $tglob =
            ref $_ eq 'Paranoid::Glob'
            ? $_
            : Paranoid::Glob->new( globs => [$_] );

        unless ( defined $tglob ) {

            # Error out
            $rv = 0;
            last;
        }

        # Add the contents of the temporary glob
        push @$glob, @$tglob;
    }

    if ($rv) {

        # Load the directory tree and execute prm
        $rv =
            $glob->recurse( $follow, 1 ) && pchmod( $errRef, $perms, $glob );
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub pchown ($$$@) {

    # Purpose:  Simulates a "chown" command in pure Perl
    # Returns:  True (1) if all targets were successfully owned,
    #           False (0) if there are any errors
    # Usage:    $rv = pchown(\%errors, $user, $group, "/foo");

    my ( $errRef, $user, $group ) = splice @_, 0, 3;
    my @targets = grep {defined} splice @_;
    my $rv = 1;
    my ( $glob, $tglob, @fstat );

    # Validate arguments
    croak 'Mandatory first argument must be a hash reference'
        unless defined $errRef && ref $errRef eq 'HASH';
    croak 'Mandatory second or third argument must be a defined user or '
        . 'group'
        unless defined $user || defined $group;
    %$errRef = ();

    $user  = -1 unless defined $user;
    $group = -1 unless defined $group;

    pdebug(
        "entering w/($errRef)($user)($group)("
            . "(@{[ join ',', map { defined $_ ? $_ : 'undef' } @targets ]})",
        PDLEVEL1
        );
    pIn();

    # Translate to UID/GID
    $user  = ptranslateUser($user)   unless $user  =~ /^-?\d+$/sm;
    $group = ptranslateGroup($group) unless $group =~ /^-?\d+$/sm;
    unless ( defined $user and defined $group ) {
        $rv = 0;
        Paranoid::ERROR =
            pdebug( 'unsuccessful at translating uid/gid', PDLEVEL1 );
    }

    # Add the contents of all the passed globs/strings
    $glob = new Paranoid::Glob;
    foreach (@targets) {

        # Make sure we're dealing with globs
        $tglob =
            ref $_ eq 'Paranoid::Glob'
            ? $_
            : Paranoid::Glob->new( globs => [$_] );

        unless ( defined $tglob ) {

            # Error out
            Paranoid::ERROR = pdebug( "failed to glob $_", PDLEVEL1 );
            $rv = 0;
            last;
        }

        # Add the contents of the temporary glob
        push @$glob, @$tglob;
    }

    if ($rv) {

        # Proceed
        pdebug( "UID: $user GID: $group", PDLEVEL2 );

        # Consolidate the entries
        $glob->consolidate;

        # Process the list
        foreach (@$glob) {

            pdebug( "processing $_", PDLEVEL2 );

            unless ( chown $user, $group, $_ ) {
                $rv = 0;
                $$errRef{$_} = $!;
                Paranoid::ERROR =
                    pdebug( "failed to adjust ownership of $_: $!",
                    PDLEVEL1 );
            }
        }
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub pchownR ($$$$@) {

    # Purpose:  Calls pchown recursively
    # Returns:  True (1) if all targets were successfully owned,
    #           False (0) if there are any errors
    # Usage:    $rv = pchownR(0, \%errors, $user, $group, "/foo");

    my ( $follow, $errRef, $user, $group ) = splice @_, 0, 4;
    my @targets = grep {defined} splice @_;
    my $rv = 1;
    my ( $glob, $tglob );

    pdebug( 'entering', PDLEVEL1 );
    pIn();

    # Create a glob object for interal use
    $glob = new Paranoid::Glob;

    # Add the contents of all the passed globs/strings
    foreach (@targets) {

        # Make sure we're dealing with globs
        $tglob =
            ref $_ eq 'Paranoid::Glob'
            ? $_
            : Paranoid::Glob->new( globs => [$_] );

        unless ( defined $tglob ) {

            # Error out
            $rv = 0;
            last;
        }

        # Add the contents of the temporary glob
        push @$glob, @$tglob;
    }

    if ($rv) {

        # Load the directory tree and execute prm
        $rv = $glob->recurse( $follow, 1 )
            && pchown( $errRef, $user, $group, $glob );
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

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
    my $b           = defined $binary ? $binary : 'undef';

    pdebug( "entering w/($b)", PDLEVEL1 );
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

$Id: Filesystem.pm,v 0.19 2010/06/03 19:01:11 acorliss Exp $

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

B<NOTE:> Previous versions of this module used the rather restrictive filename
regexes for detainting arguments.  This is now handled by the
L<Paranoid::Glob> module, which detaints to pretty much everything a
filesystem can handle.  Many of what used to be fatal errors are no longer so.
Programmatic errors are still fatal, but errors which may be due to user input
are safely errored out, allowing program execution to continue.

=head1 SUBROUTINES/METHODS

=head2 pmkdir

  $rv = pmkdir("/foo", 0750);

This function simulates a 'mkdir -p {path}', returning false if it fails for
any reason other than the directory already being present.  The second
argument (permissions) is optional, but if present should be an octal number.
Shell-style globs are supported as the path argument.

If you need to make a directory that includes characters which would normally
be interpreted as shell expansion characters you can offer a B<Paranoid::Glob>
object as the path argument instead.  Creating such an object while passing it
a I<literal> boolean true value will prevent any shell expansion from
happening.

This method also allows you to call B<pmkdir> with a list of directories to
create, rather than just relying upon shell expansion to construct the list.

=head2 prm

  $rv = prm(\%errors, "/foo", "/bar/*");

This function unlinks non-directories and rmdir's directories.  File 
arguments are processed through B<pglob> and expanded into multiple
targets if globs are detected.

The error message from each failed operation will be placed into the passed
hash ref using the filename as the key.

B<NOTE>:  If you ask it to delete something that's not there it will silently
succeed.  After all, not being there is what you wanted anyway, right?

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
unneeded path artifacts.  If an error occurs (like circular link references
or the target being nonexistent) this function will return undef.
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

B<NOTE:> This function is now just a wrapper around L<Paranoid::Glob>.  It may
be advantageous for you to use it directly in lieu of B<pglob>.

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

L<Carp>

=item o

L<Cwd>

=item o

L<Errno>

=item o

L<Fcntl>

=item o

L<Paranoid>

=item o

L<Paranoid::Debug>

=item o

L<Paranoid::Input>

=item o

L<Paranoid::Glob>

=back

=head1 BUGS AND LIMITATIONS

B<ptranslateLink> is probably pointless for 99% of the uses out there, you're
better off using B<Cwd>'s B<realpath> function instead.  The only thing it can
do differently is translating a single link itself, without translating any
additional symlinks found in the preceding path.  But, again, you probably
won't want that in most circumstances.

All of the B<*R> recursive functions have the potential to be very expensive
in terms of memory usage.  In an attempt to be fast (and reduce excessive 
function calls and stack depth) it utilizes L<Paranoid::Glob>'s B<recurse> 
method.  In essence, this means that the entire directory tree is loaded into 
memory at once before any operations are performed.

For the most part functions meant to simulate userland programs try to act
just as those programs would in a shell environment.  That includes filtering
arguments through shell globbing expansion, etc.  Should you have a filename
that should be treated as a literal string you should put it into a
L<Paranoid::Glob> object as a literal first, and then hand the glob to the
functions.

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

