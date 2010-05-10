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

__EOF__

# Create the makefile
WriteMakefile(
  NAME            => 'Paranoid',
  ABSTRACT        => 'General function library for safer, more secure programming',
  AUTHOR          => 'Arthur Corliss <corliss@digitalmages.com>',
  VERSION_FROM    => 'lib/Paranoid.pm',
  PREREQ_PM       => {
                     'Carp'             => 0,
                     'Errno'            => 0,
                     'Fcntl'            => 0,
                     'File::Glob'       => 0,
                     'POSIX'            => 0,
                     },
  ($ExtUtils::MakeMaker::VERSION ge '6.30_00' ? (
    LICENSE => 'perl',) : ()),
  );

exit 0;
