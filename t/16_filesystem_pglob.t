#!/usr/bin/perl -T
# 16_filesystem_pglob.t

use Test::More tests => 16;
use Paranoid;
use Paranoid::Debug;
use Paranoid::Filesystem;
use Paranoid::Glob;

#PDEBUG = 20;

psecureEnv();

use strict;
use warnings;

my (@tmp, %errors);

# Old-style invocation
ok( pglob( './t/*', \@tmp ), 'pglob 1' );
ok( $#tmp, 'pglob 2' );
ok( grep( m#^./t/99_pod.t$#sm, @tmp ), 'pglob 3' );

ok( pglob( './t/9[0-9]*.{t,v}', \@tmp ), 'pglob 4' );
is( $#tmp, 1, 'pglob 5' );
ok( grep( m#^./t/99_pod.t$#sm, @tmp ), 'pglob 6' );

ok( pglob( './t/8[0-9]*.{t,v}', \@tmp ), 'pglob 7' );
is( $#tmp, -1, 'pglob 8' );

# New-style invocation
ok( pglob( \%errors, \@tmp, './t/*' ), 'pglob 9' );
ok( $#tmp, 'pglob 10' );
ok( grep( m#^./t/99_pod.t$#sm, @tmp ), 'pglob 11' );

ok( pglob( \%errors, \@tmp, './t/9[0-9]*.{t,v}' ), 'pglob 12' );
is( $#tmp, 1, 'pglob 13' );
ok( grep( m#^./t/99_pod.t$#sm, @tmp ), 'pglob 14' );

ok( pglob( \%errors, \@tmp, './t/8[0-9]*.{t,v}' ), 'pglob 15' );
is( $#tmp, -1, 'pglob 16' );

# end 16_filesystem_pglob.t
