use common::sense;
package Parse::Matroska::Utils;

use Exporter;
our @ISA       = qw{Exporter};
our @EXPORT_OK = qw{uniq uncamelize};

# from List::MoreUtils
sub uniq(@) {
  my %seen;
  return grep { !$seen{$_}++ } @_;
}

# CAMELCasedString -> camel_cased_string
sub uncamelize($) {
    my $_ = shift;
    # lc followed by UC: lc_UC
    s/(?<=[a-z])([A-Z])/_$1/g;
    # UC followed by two lc: _UClclc
    s/([A-Z])(?=[a-z]{2})/_$1/g;
    # strip leading _ that the second regexp might add; lowercase all
    s/^_//; lc
}