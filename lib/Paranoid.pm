# Paranoid -- Paranoia support for safer programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Paranoid.pm,v 0.25 2010/05/05 00:20:17 acorliss Exp $
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

package Paranoid;

use 5.006;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS);
use base qw(Exporter);

($VERSION) = ( q$Revision: 0.25 $ =~ /(\d+(?:\.(\d+))+)/sm );

@EXPORT      = qw(psecureEnv);
@EXPORT_OK   = qw(psecureEnv);
%EXPORT_TAGS = ( all => [qw(psecureEnv)], );

#####################################################################
#
# Module code follows
#
#####################################################################

#BEGIN {
#die "This module requires taint mode to be enabled!\n" unless
#  ${^TAINT} == 1;
#delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
#$ENV{PATH} = '/bin:/sbin:/usr/bin:/usr/sbin';
#no ops qw(backtick system exec);
#  :subprocess = system, backtick, exec, fork, glob
#  :dangerous = syscall, dump, chroot
#  :others = mostly IPC stuff
#  :filesys_write = link, unlink, rename, mkdir, rmdir, chmod,
#                   chown, fcntl
#  :sys_db = getpwnet, etc.
#}

sub psecureEnv (;$) {

    # Purpose:  To delete taint-unsafe environment variables and to sanitize
    #           the PATH variable
    # Returns:  True (1) -- no matter what
    # Usage:    psecureEnv();

    my $path = shift;

    $path = '/bin:/usr/bin' unless defined $path;

    delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
    $ENV{PATH} = $path;
    if ( exists $ENV{TERM} ) {
        if ( $ENV{TERM} =~ /^([\w\+\.\-]+)$/sm ) {
            $ENV{TERM} = $1;
        } else {
            $ENV{TERM} = 'vt100';
        }
    }

    return 1;
}

{
    my $errorMsg = '';

    sub ERROR : lvalue {

        # Purpose:  To store/retrieve a string error message
        # Returns:  Scalar string
        # Usage:    $errMsg = Paranoid::ERROR;
        # Usage:    Paranoid::ERROR = $errMsg;

        $errorMsg;
    }
}

1;

__END__

=head1 NAME

Paranoid - Paranoia support for safer programs

=head1 VERSION

$Id: Paranoid.pm,v 0.25 2010/05/05 00:20:17 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid;

  $errMsg = Paranoid::ERROR;

  psecureEnv("/bin:/usr/bin");

=head1 DESCRIPTION

This collection of modules started out as modules which perform things
(debatably) in a safer and taint-safe manner.  Since then it's also grown to
include functionality that fit into the same framework and conventions of the
original modules, including keeping the debug hooks for command-line
debugging.

All the modules below are intended to be used directly in your programs if you
need the functionality they provide.

This module does provide one function meant to secure your environment 
enough to satisfy taint-enabled programs, and as a container which holds the 
last reported error from any code in the Paranoid framework.

=head1 SUBROUTINES/METHODS

=head2 psecureEnv

  psecureEnv("/bin:/usr/bin");

This function deletes some of the dangerous environment variables that can be
used to subvert perl when being run in setuid applications.  It also sets the
path, either to the passed argument (if passed) or a default of
"/bin:/usr/bin".

=head2 Paranoid::ERROR

  $errMsg = Paranoid::ERROR;
  Paranoid::ERROR = $errMsg;

This lvalue function is not exported and must be referenced via the 
B<Paranoid> namespace.

=head1 TAINT NOTES

Taint-mode programming can be somewhat of an adventure until you know all the
places considered dangerous under perl's taint mode.  The following functions
should generally have their arguments detainted before using:

  exec        system      open        glob
  unlink      mkdir       chdir       rmdir
  chown       chmod       umask       utime
  link        symlink     kill        eval
  truncate    ioctl       fcntl       chroot
  setpgrp     setpriority syscall     socket
  socketpair  bind        connect

=head1 DEPENDENCIES

While this module itself doesn't have any external dependencies various child
modules do.  Please check their documentation for any particulars should you
use them.

=head1 SEE ALSO

The following modules are available for use.  You should check their POD for
specifics on use:

=over

=item o

L<Paranoid::Args>: Command-line argument parsing functions

=item o

L<Paranoid::BerkeleyDB>: OO-oriented BerkelyDB access with concurrent access
capabilities

=item o

L<Paranoid::Data>: Misc. data manipulation functions

=item o

L<Paranoid::Debug>: Command-line debugging framework and functions

=item o

L<Paranoid::Filesystem>: Filesystem operation functions

=item o

L<Paranoid::Glob>: Paranoid Glob objects

=item o

L<Paranoid::Input>: Input-related functions (file reading, detainting)

=item o

L<Paranoid::Lockfile>: Lockfile support

=item o

L<Paranoid::Log>: Unified logging framework and functions

=item o

L<Paranoid::Module>: Run-time module loading functions

=item o

L<Paranoid::Network>: Network-related functions

=item o

L<Paranoid::Process>: Process management functions

=back

=head1 BUGS AND LIMITATIONS

If your application is sensitive to performance issues then you may
be better off not using these modules.  The primary focus was on security,
robustness, and diagnostics.  That said, there's probably a lot of room for
improvement on the performance front.

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

