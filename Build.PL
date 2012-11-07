
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "Data::Dumper" => 0,
    "File::Spec::Functions" => 0,
    "FindBin" => 0,
    "Module::Build" => "0.3601",
    "Test::More" => "0.94"
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Module collection to parse Matroska files.",
  "dist_author" => [
    "Kovensky <diogomfranco\@gmail.com>"
  ],
  "dist_name" => "Parse-Matroska",
  "dist_version" => "0.003",
  "license" => "open_source",
  "module_name" => "Parse::Matroska",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
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
    "perl" => "5.008",
    "strict" => 0,
    "warnings" => 0
  },
  "script_files" => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
