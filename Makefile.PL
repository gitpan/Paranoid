use ExtUtils::MakeMaker;
use 5.006;

print << "__EOF__";
This module contains a few modules with external (non-core) module
dependencies.  This only affects those few modules, with the bulk of this
collection being pure (core) Perl.

The following modules have dependencies:

  Module                           Dependencies
  ===========================================================
  Paranoid::BerkeleyDB             BerkeleyDB
  Paranoid::Log::Email             Net::SMTP
  Paranoid::Log::Syslog            Unix::Syslog

These modules will still be installed, they just won't be usable until those
dependencies are resolved.

The following modules have optional dependencies:

  Module                           Dependencies
  ===========================================================
  Paranoid::Network                Socket6

You only need this installed if you wish to work with IPv6 networks in
addition to IPv4.

__EOF__

# Required modules
my %reqMods = (
    'Carp'             => 0,
    'Errno'            => 0,
    'Fcntl'            => 0,
    'File::Glob'       => 0,
    'POSIX'            => 0,
    );

my $required = << "__EOF__";

    Carp:                $reqMods{'Carp'}
    Errno:               $reqMods{'Errno'}
    Fcntl:               $reqMods{'Fcntl'}
    File::Glob:          $reqMods{'File::Glob'}
    POSIX:               $reqMods{'POSIX'}
__EOF__

my %optMods;

# Populate %optMods with minimal versions
if ( eval 'require Unix::Syslog; 1;' ) {
  $optMods{'Unix::Syslog'} = 1.1;
}
if ( eval 'require Net::SMTP; 1;' ) {
  $optMods{'Net::SMTP'} = 0;
}
if ( eval 'require BerkeleyDB; 1;' ) {
  $optMods{'BerkeleyDB'} = 0.32;
}
if ( eval 'require Socket; require Socket6; 1;' ) {
  $optMods{'Socket6'} = 0.23;
}

my $recommended = << "__EOF__";

    Unix::Syslog:        $optMods{'Unix::Syslog'}
    Net::SMTP:           $optMods{'Net::SMTP'}
    BerkeleyDB:          $optMods{'BerkeleyDB'}
    Socket6:             $optMods{'Socket6'}
__EOF__

# Create the makefile
WriteMakefile(
  NAME            => 'Paranoid',
  ABSTRACT        => 'General function library for safer, more secure programming',
  AUTHOR          => 'Arthur Corliss <corliss@digitalmages.com>',
  VERSION_FROM    => 'lib/Paranoid.pm',
  PREREQ_PM       => { %reqMods, %optMods },
  ($ExtUtils::MakeMaker::VERSION ge '6.30_00' ? (
    LICENSE => 'perl',
    META_ADD => { 'recommends' => $recommended ,
                  'requires'   => $required }) : ()),
  );

exit 0;
