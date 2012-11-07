
use strict;
use warnings;

use 5.008;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Module collection to parse Matroska files.",
  "AUTHOR" => "Kovensky <diogomfranco\@gmail.com>",
  "BUILD_REQUIRES" => {
    "Data::Dumper" => 0,
    "File::Spec::Functions" => 0,
    "FindBin" => 0,
    "Module::Build" => "0.3601",
    "Test::More" => "0.94"
  },
  "CONFIGURE_REQUIRES" => {
    "Module::Build" => "0.3601"
  },
  "DISTNAME" => "Parse-Matroska",
  "EXE_FILES" => [],
  "LICENSE" => "open_source",
  "NAME" => "Parse::Matroska",
  "PREREQ_PM" => {
    "Carp" => 0,
    "Encode" => 0,
    "Exporter" => 0,
    "IO::File" => 0,
    "IO::Handle" => 0,
    "List::Util" => 0,
    "Math::BigInt" => 0,
    "Math::BigRat" => 0,
    "Scalar::Util" => 0,
    "bigrat" => 0,
    "constant" => 0,
    "strict" => 0,
    "warnings" => 0
  },
  "VERSION" => "0.003",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.56) } ) {
  my $br = delete $WriteMakefileArgs{BUILD_REQUIRES};
  my $pp = $WriteMakefileArgs{PREREQ_PM};
  for my $mod ( keys %$br ) {
    if ( exists $pp->{$mod} ) {
      $pp->{$mod} = $br->{$mod} if $br->{$mod} > $pp->{$mod};
    }
    else {
      $pp->{$mod} = $br->{$mod};
    }
  }
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



