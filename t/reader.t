#! /usr/bin/env perl

use common::sense;
use Test::More tests => 12;
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

done_testing();
