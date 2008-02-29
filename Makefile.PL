use ExtUtils::MakeMaker;

# Override method in order to make sure test script is run with taint-mode
# enabled.
@ISA = qw(ExtUtils::MM_Any);
sub MY::test_via_script {
  my($self, $perl, $script) = @_;
  return $self->SUPER::test_via_script("PERL_DL_NONLAZY=1 $perl -T", $script);
}

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
  PREREQ_PM       => {},
  );

exit 0;
