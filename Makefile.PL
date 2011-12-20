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
  Paranoid::Network::Socket        Socket6

You only need this installed if you wish to work with IPv6 networks in
addition to IPv4.  If you're running Perl 5.14 or higher you don't need it
at all, since they support IPv6 from that version.

__EOF__

# Required modules
my %reqMods = (
    'Carp'             => 0,
    'Errno'            => 0,
    'Fcntl'            => 0,
    'File::Glob'       => 0,
    'POSIX'            => 0,
    );
my %optMods = (
  'Unix::Syslog'    => 1.1,
  'Net::SMTP'       => 0,
  'BerkeleyDB'      => 0.32,
  'Socket6'         => 0.23,
  );

# Create the makefile
WriteMakefile(
  NAME            => 'Paranoid',
  ABSTRACT        => 'General function library for safer, more secure programming',
  AUTHOR          => 'Arthur Corliss <corliss@digitalmages.com>',
  VERSION_FROM    => 'lib/Paranoid.pm',
  PREREQ_PM       => { %reqMods },
  ($ExtUtils::MakeMaker::VERSION ge '6.30_00' ? (
    LICENSE => 'perl',
    META_ADD => { 'recommends' => { %optMods } ,
                  'requires'   => { %reqMods } }) : ()),
  );

exit 0;
