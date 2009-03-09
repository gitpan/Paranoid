#!/usr/bin/perl -T
# 10_log_email.t

use Test::More tests => 14;
use Paranoid;
use Paranoid::Log;
use Paranoid::Module;

use strict;
use warnings;

psecureEnv();

my $rv;

SKIP: {
    skip( 'Net::SMTP not found', 14 )
        unless loadModule('Paranoid::Log::Email')
            and exists $ENV{USER};

    # Bad mailhost, should fail
    ok( enableFacility(
            'email', 'email', 'warn', '=', 'localhst0.',
            "$ENV{USER}\@localhost", undef, 'Test message -- please ignore'
        ),
        'enableFacility 1'
      );
    ok( !plog( "warn", "this is a test" ), 'plog 1' );
    ok( disableFacility('email'), 'disableFacility 1' );

    # Good mailhost, should succeed (if mail services are running)
    ok( enableFacility(
            'email', 'email', 'warn', '=', 'localhost',
            "$ENV{USER}\@localhost", undef, 'Test message -- please ignore'
        ),
        'enableFacility 2'
      );
    $rv = plog( "warn", "this is a test" );
    ok( disableFacility('email'), 'disableFacility 2' );

    skip( 'No local mail services running', 9 ) unless $rv;

    ok( enableFacility(
            'email',
            'email',
            'warn',
            '=',
            'localhost',
            [ "$ENV{USER}\@localhost", "$ENV{USER}\@localhost" ],
            undef,
            'Test message -- please ignore'
        ),
        'enableFacility 3'
      );
    ok( plog( "warn", "this is a test" ), 'plog 3' );
    ok( disableFacility('email'), 'disableFacility 3' );

    # This following test should fail, but its entirely possible that it
    # doesn't if someone has a *really* stupid mail config
    ok( enableFacility(
            'email', 'email', 'warn', '=', 'localhost',
            "$ENV{USER}\@localhost", 'user@fooo.coom.neeeet.',
            'Test message -- please ignore'
        ),
        'enableFacility 4'
      );
    $rv = plog( "warn", "this is a test" );
    if ($rv) {
      warn "test 'plog 4' should have failed, but didn't.\n";
      warn "Ignoring since this could be a MTA config issue.\n";
    }
    ok( 1, 'plog 4' );
    ok( disableFacility('email'), 'disableFacility 4' );

    # The same goes for this -- if it succeeds it may be a mail config issue
    ok( enableFacility(
            'email',     'email',
            'warn',      '=',
            'localhost', "iHopeTheresNoSuchUserReallyReallyBad\@localhost",
            undef,       'Test message -- please ignore'
        ),
        'enableFacility 5'
      );
    $rv = plog( "warn", "this is a test" );
    if ($rv) {
      warn "test 'plog 5' should have failed, but didn't.\n";
      warn "Ignoring since this could be a MTA config issue.\n";
    }
    ok( 1, 'plog 5' );
    ok( disableFacility('email'), 'disableFacility 5' );
}

# end 10_log_email.t
