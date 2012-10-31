use strict;
use warnings;

package Parse::Matroska::Utils;
=head1 NAME

Parse::Matroska::Utils

=head1 DESCRIPTION

Internally-used helper functions

=cut

use Exporter;
our @ISA       = qw{Exporter};
our @EXPORT_OK = qw{uniq uncamelize};

=head1 FUNCTIONS

=over

=item uniq(@array)

The same as L<List::MoreUtils/"uniq LIST">.
Included to avoid depending on it.

=cut
sub uniq(@) {
  my %seen;
  return grep { !$seen{$_}++ } @_;
}

=item uncamelize($string)

Converts a "StringLikeTHIS" into a
"string_like_this".

=cut
sub uncamelize($) {
    local $_ = shift;
    # lc followed by UC: lc_UC
    s/(?<=[a-z])([A-Z])/_$1/g;
    # UC followed by two lc: _UClclc
    s/([A-Z])(?=[a-z]{2})/_$1/g;
    # strip leading _ that the second regexp might add; lowercase all
    s/^_//; lc
}

=back

=head1 AUTHOR

Diogo Franco <diogomfranco@gmail.com>, aka Kovensky.

=head1 LICENSE

The FreeBSD license, equivalent to the ISC license.
