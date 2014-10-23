# Paranoid::Process -- Process management support for paranoid programs
#
# (c) 2005, Arthur Corliss <corliss@digitalmages.com>
#
# $Id: Process.pm,v 1.01 2010/05/10 04:55:07 acorliss Exp $
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

package Paranoid::Process;

use 5.006;

use strict;
use warnings;
use vars qw($VERSION @EXPORT @EXPORT_OK %EXPORT_TAGS);
use base qw(Exporter);
use Paranoid;
use Paranoid::Debug qw(:all);
use POSIX qw(getuid setuid setgid WNOHANG setsid);
use Carp;

($VERSION) = ( q$Revision: 1.01 $ =~ /(\d+(?:\.(\d+))+)/sm );

@EXPORT    = qw(switchUser daemonize);
@EXPORT_OK = qw(MAXCHILDREN      childrenCount   installChldHandler
    sigchld          pfork           ptranslateUser
    ptranslateGroup  switchUser      pcapture
    daemonize);
%EXPORT_TAGS = (
    all => [
        qw(MAXCHILDREN      childrenCount   installChldHandler
            sigchld          pfork           ptranslateUser
            ptranslateGroup  switchUser      pcapture
            daemonize)
        ],
    pfork => [
        qw(MAXCHILDREN      childrenCount   installChldHandler
            sigchld          pfork           daemonize)
        ],
        );

#####################################################################
#
# Module code follows
#
#####################################################################

{
    my $maxChildren = 0;
    my $numChildren = 0;
    my $chldRef     = undef;

    sub MAXCHILDREN : lvalue {

        # Purpose:  Gets/sets $maxChildren
        # Returns:  $maxChildren
        # Usage:    $max = MAXCHILDREN;
        # Usage:    MAXCHILDREN = 20;

        $maxChildren;
    }
    sub childrenCount () { return $numChildren }
    sub _incrChildren () { $numChildren++ }
    sub _decrChildren () { $numChildren-- }

    sub installChldHandler ($) {

        # Purpose:  Installs a code reference to execute whenever a child
        #           exits
        # Returns:  True (1)
        # Usage:    installChldHandler(\&foo);

        $chldRef = shift;

        croak 'installChldHandler passed no sub ref!'
            unless defined $chldRef && ref($chldRef) eq 'CODE';
        return 1;
    }
    sub _chldHandler () { return $chldRef }
}

sub sigchld () {

    # Purpose:  Default signal handler for SIGCHLD
    # Returns:  True (1)
    # Usage:    $SIG{CHLD} = \&sigchld;

    my ( $osref, $pid );
    my $sref = _chldHandler();

    # Remove the signal handler so we're not preempted
    $osref = $SIG{CHLD};
    $SIG{CHLD} = sub {1};

    # Process children exit values
    do {
        $pid = waitpid -1, WNOHANG;
        if ( $pid > 0 ) {
            _decrChildren();
            pdebug( "child $pid reaped w/rv: $?", PDLEVEL1 );

            # Call the user's sig handler if defined
            &$sref( $pid, $? ) if defined $sref;
        }
    } until $pid < 1;

    # Reinstall the signal handler
    $SIG{CHLD} = $osref;

    return 1;
}

sub daemonize () {

    # Purpose:  Daemonizes process and disassociates with the terminal
    # Returns:  True unless there are errors.
    # Usage:    daemonize();

    my ( $rv, $pid );

    pdebug( 'entering', PDLEVEL1 );
    pIn();

    $pid = fork;

    # Exit if we're the parent process
    exit 0 if $pid;

    if ( defined $pid ) {

        # Fork was successful, close parent file descriptors
        $rv = open(STDIN, '/dev/null') and open(STDOUT, '>/dev/null');

        # Create a new process group
        unless ($rv) {
            setsid();
            $rv = open STDERR, '>&STDOUT';
            die "Can't dup stdout: $!" unless $rv;
            chdir '/';
        }

    } else {
        Paranoid::ERROR =
            pdebug( "Failed to daemonize process: $!", PDLEVEL1 );
        $rv = 0;
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub pfork () {

    # Purpose:  Replacement for Perl's fork function.  Blocks until a child
    #           exists if MAXCHILDREN is exceeded.
    # Returns:  Return value of children handler if installed, otherwise
    #           undef.
    # Usage:    $rv = pfork();

    my $max = MAXCHILDREN();
    my ( $rv, $rvarg );

    pdebug( 'entering', PDLEVEL1 );
    pIn();

    # Check children limits and wait, if necessary
    if ($max) {
        while ( $max <= childrenCount() ) { sleep 1 }
    }

    # Fork and return
    $rv = fork;
    _incrChildren() if defined $rv;
    $rvarg = defined $rv ? $rv : 'undef';

    pOut();
    pdebug( "leaving w/rv: $rvarg", PDLEVEL1 );

    return $rv;
}

sub ptranslateUser ($) {

    # Purpose:  Translates a string account name into the UID
    # Returns:  UID if found, undef if not
    # Usage:    $uid = ptranslateUser($user);

    my $user = shift;
    my ( $uuid, @pwentry, $rv, $rvarg );

    # Validate arguments
    croak 'Mandatory first argument must be a defined username'
        unless defined $user;

    pdebug( "entering w/($user)", PDLEVEL1 );
    pIn();

    setpwent;
    do {
        @pwentry = getpwent;
        $uuid = $pwentry[2] if @pwentry && $user eq $pwentry[0];
    } until defined $uuid || !@pwentry;
    endpwent;
    $rv = $uuid if defined $uuid;
    $rvarg = defined $rv ? $rv : 'undef';

    pOut();
    pdebug( "leaving w/rv: $rvarg", PDLEVEL1 );

    return $rv;
}

sub ptranslateGroup ($) {

    # Purpose:  Translates a string group name into the UID
    # Returns:  GID if found, undef if not
    # Usage:    $gid = ptranslateGroup($group);

    my $group = shift;
    my ( $ugid, @pwentry, $rv, $rvarg );

    # Validate arguments
    croak 'Mandatory first argument must be a defined group name'
        unless defined $group;

    pdebug( "entering w/($group)", PDLEVEL1 );
    pIn();

    setgrent;
    do {
        @pwentry = getgrent;
        $ugid = $pwentry[2] if @pwentry && $group eq $pwentry[0];
    } until defined $ugid || !@pwentry;
    endgrent;
    $rv = $ugid if defined $ugid;
    $rvarg = defined $rv ? $rv : 'undef';

    pOut();
    pdebug( "leaving w/rv: $rvarg", PDLEVEL1 );

    return $rv;
}

sub switchUser ($;$) {

    # Purpose:  Switches to the user/group specified
    # Returns:  True (1) if successful, False (0) if not
    # Usage:    $rv = swithUser($user);
    # Usage:    $rv = swithUser($user, $group);

    my $user  = shift;
    my $group = shift;
    my $uarg  = defined $user ? $user : 'undef';
    my $garg  = defined $group ? $group : 'undef';
    my $rv    = 1;
    my ( @pwentry, $duid, $dgid );

    # Validate arguments
    croak 'Mandatory argument of either user or group must be passed'
        unless defined $user || defined $group;

    pdebug( "entering w/($uarg)($garg)", PDLEVEL1 );
    pIn();

    # First switch the group
    if ( defined $group ) {

        # Look up named group
        unless ( $group =~ /^\d+$/sm ) {
            $dgid = ptranslateGroup($group);
            unless ( defined $dgid ) {
                Paranoid::ERROR =
                    pdebug( "couldn't identify group ($group)", PDLEVEL1 );
                $rv = 0;
            }
        }

        # Switch to group
        if ($rv) {
            pdebug( "switching to GID $dgid", PDLEVEL2 );
            unless ( setgid($dgid) ) {
                Paranoid::ERROR =
                    pdebug( "couldn't switch to group ($group): $!",
                    PDLEVEL1 );
                $rv = 0;
            }
        }
    }

    # Second, switch the user
    if ( $rv && defined $user ) {

        # Look up named user
        unless ( $user =~ /^\d+$/sm ) {
            $duid = ptranslateUser($user);
            unless ( defined $duid ) {
                Paranoid::ERROR =
                    pdebug( "couldn't identify user ($user)", PDLEVEL1 );
                $rv = 0;
            }
        }

        # Switch to user
        if ($rv) {
            pdebug( "switching to UID $duid", PDLEVEL2 );
            unless ( setuid($duid) ) {
                Paranoid::ERROR =
                    pdebug( "couldn't switch to user ($user): $!", PDLEVEL1 );
                $rv = 0;
            }
        }
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

sub pcapture ($$$) {

    # Purpose:  Captures the output and exit code of the specified shell
    #           command.  Output incorporates STDERR via redirection.
    # Returns:  True (1) if command exits cleanly, False (0) otherwise
    # Usage:    $rv = pcapture($cmd, \$crv, \$out);

    my $cmd  = shift;
    my $cref = shift;
    my $oref = shift;
    my $rv   = -1;
    my ( $sigchld, $cored, $signal );

    # Validate arguments
    croak 'Mandatory first argument must be a defined shell command string'
        unless defined $cmd;
    croak 'Mandatory second argument must be a scalar reference'
        unless defined $cref && ref $cref eq 'SCALAR';
    croak 'Mandatory third argument must be a scalar reference'
        unless defined $oref && ref $oref eq 'SCALAR';

    pdebug( "entering w/($cmd)($cref)($oref)", PDLEVEL1 );
    pIn();

    # Massage the command string
    $cmd = "( $cmd ) 2>&1";

    # Backup SIGCHLD handler and set it to something safe
    if ( defined $SIG{CHLD} ) {
        $sigchld = $SIG{CHLD};
        $SIG{CHLD} = sub {1};
    }

    # Execute and snarf the output
    pdebug( 'executing command', PDLEVEL2 );
    $$oref  = `$cmd`;
    $$cref  = $?;
    $cored  = $$cref & 128;
    $signal = $$cref & 127;
    pdebug( "command exited with raw rv: $$cref", PDLEVEL2 );

    # Restore SIGCHLD handler
    $SIG{CHLD} = $sigchld if defined $SIG{CHLD};

    # Check the return value
    if ( $$cref == -1 or $$cref == 32512 ) {

        # Command failed to execute
        Paranoid::ERROR = pdebug( "command failed to execute: $!", PDLEVEL1 );
        $rv = -1;

    } elsif ($signal) {

        # Exited with signal (and core?)
        Paranoid::ERROR =
            pdebug( "command died with signal: $signal", PDLEVEL1 );
        pdebug( "command exited with core dump", PDLEVEL1 ) if $cored;
        $rv = -1;

    } else {

        # Command exited normally
        $$cref >>= 8;
        $rv = $$cref == 0 ? 1 : 0;
        pdebug( "command exited with rv: $$cref", PDLEVEL1 );
    }

    pOut();
    pdebug( "leaving w/rv: $rv", PDLEVEL1 );

    return $rv;
}

1;

__END__

=head1 NAME

Paranoid::Process - Process Management Functions

=head1 VERSION

$Id: Process.pm,v 1.01 2010/05/10 04:55:07 acorliss Exp $

=head1 SYNOPSIS

  use Paranoid::Process;

  $rv = daemonize();

  MAXCHILDREN = 100;

  $SIG{CHLD} = \&sigchld;
  $count = childrenCount();
  installChldHandler($sub);
  $rv = pfork();

  $uid = ptranslateUser("foo");
  $gid = ptranslateGroup("foo");
  $rv = switchUser($user, $group);

  $rv = pcapture($cmd, \$crv, \$out);

=head1 DESCRIPTION

This module provides a few functions meant to make life easier when managing
processes.  The following export targets are provided:

  all               All functions within this module
  pfork             All child management functions

Only the functions B<switchUser> and B<daemonize> are currently exported by 
default.

=head1 SUBROUTINES/METHODS

=head2 MAXCHILDREN

Setting this lvalue subroutine sets a limit to how many children will be 
forked at a time by B<pfork>.  The default is zero, which allows unlimited 
children.  Once the limit is met pfork becomes a blocking call until a child 
exits so the new one can be spawned.

=head2 childrenCount

  $count = childrenCount();

This function returns the current number of children spawned by B<pfork>.

=head2 installChldHandler

  installChldHandler($sub);

This function takes a reference to a subroutine.  If used the subroutine will
be called every time a child exits.  That subroutine will be called with the
child's PID and exit value as arguments.

=head2 sigchld

  $SIG{CHLD} = \&sigchld;

This function decrements the child counter necessary for pfork's operation, as
well as calling the user's signal handler with each child's PID and exit
value.

=head2 daemonize

    $rv = daemonize();

This function forks a child who reopens all STD* filehandles on /dev/null and 
starts a new process group.  The parent exits cleanly.  If the fork fails for
any reason it returns a false value.  The child will also change its directory
to B</>.

=head2 pfork

  $rv = pfork();

This function should be used in lieu of Perl's fork if you want to take
advantage of a blocking fork call that respects the MAXCHILDREN limit.  Use of
this function, however, also assumes the use of B<sigchld> as the signal
handler for SIGCHLD.

=head2 ptranslateUser

  $uid = ptranslateUser("foo");

This function takes a username and returns the corresponding UID as returned
by B<getpwent>.  If no match is found it returns undef.

=head2 ptranslateGroup

  $gid = ptranslateGroup("foo");

This function takes a group name and returns the corresponding GID as returned
by B<getgrent>.  If no match is found it returns undef.

=head2 switchUser

  $rv = switchUser($user, $group);

This function can be fed one or two arguments, both either named user or
group, or UID or GID.  Both user and group arguments are optional as long as
the other is called.  In other words, you can pass undef for one of the
arguments, but not for both.  If you're only switching the user you can pass
only the user argument.

=head2 pcapture

  $rv = pcapture($cmd, \$crv, \$out);

This function executes the passed shell command and returns one of the following
three values:

  RV    Description
  =======================================================
  -1    Command failed to execute or died with signal
   0    Command executed but exited with a non-0 RV
   1    Command executed and exited with a 0 RV

The actual return value is populated in the passed scalar reference, while all
STDERR/STDOUT output is stored in the last scalar reference.  Any errors
executing the command will have the error string stored in B<Paranoid::ERROR>.

If the command exited cleanly it will automatically be bit shifted eight
bits.

B<NOTE:> Unlike many other functions in this suite it is up to you to detaint
the command passed to this function yourself.  There's simply no way for me to
know ahead of time what kind of convoluted arguments you might be handing this
call before system is called.  Failing to detaint that argument will cause
your script to exit under taint mode.

=head1 DEPENDENCIES

=over

=item o

L<Paranoid>

=item o

L<Paranoid::Debug>

=item o

L<POSIX>

=back

=head1 EXAMPLES

=head2 pfork

This following example caps the number of children processes to three at a
time:

  $SIG{CHLD}  = \&sigchld;
  MAXCHILDREN = 3;
  for (1 .. 5) {

    # Only the children execute the following block
    unless ($pid = pfork()) {
      # ....
      exit 0;
    }
  }

You can also install a child-exit routine to be called by sigchld.
For instance, to track the children's history in the parent:

  sub recordChild ($$) {
    my ($cpid, $cexit) = @_;

    push(@chistory, [$cpid, $cexit]);
  }

  installChldHandler(\&recordChild);
  for (1 .. 5) {
    unless ($pid = pfork()) {
      # ....
      exit $rv;
    }
  }

  # Prints the child process history
  foreach (@chistory) { print "PID: $$_[0] EXIT: $$_[1]\n" };

=head1 BUGS AND LIMITATIONS

There's a bug in an current versions of Perl where B<ptranslateGroup> can 
return negative numbers instead the actual GID.  This is due to the platform
supporting unsigned integers for the GID, but Perl was casting it as a signed
integer.  A patch has been submitted to blead-perl.

On Solaris B<pcapture> doesn't return a -1 for non-existant commands, but a 0.
On Linux this appears to work as intended.

=head1 AUTHOR

Arthur Corliss (corliss@digitalmages.com)

=head1 LICENSE AND COPYRIGHT

This software is licensed under the same terms as Perl, itself. 
Please see http://dev.perl.org/licenses/ for more information.

(c) 2005, Arthur Corliss (corliss@digitalmages.com)

