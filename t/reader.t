#! /usr/bin/env perl

use strict;
use warnings;
use Test::More tests => 14;
use FindBin;
use Data::Dumper;

BEGIN {
    use_ok("Parse::Matroska::Reader");
}

my $path = "$FindBin::Bin/vectors/dist.ini.mkv";

ok -e $path, "vectors/dist.ini.mkv is present";
ok my $r = Parse::Matroska::Reader->new($path), "Reader can be instantiated";

ok my $elem = $r->read_element, "Reads an EBML element correctly";
is $elem->{name}, "EBML", "Read EBML ID corresponds to the expected ID";
is $elem->{depth}, 0, "Read EBML Element depth is correct";

is $elem->{type}, 'sub', "EBML element has children";
ok my $chld = $elem->next_child, "Can read the first child of the element";

# this is to prevent exhaustively searching files
# specially bad on pipes
ok ! $elem->children_by_name("DocType"), "Can't find DocType element without populating";

$elem->populate_children;

ok $chld = $elem->children_by_name("DocType"), "Can find DocType element after populating";
is $chld->{name}, "DocType", "Element found is indeed DocType";
is $chld->{value}, "matroska", "DocType is 'matroska'";

$r->close;

my $test_str = "\x1a\x45\xdf\xa3\xa3";
ok $r->open(\$test_str), "Can open string readers";
ok $elem = $r->read_element, "Can read a single element from string";

done_testing();
