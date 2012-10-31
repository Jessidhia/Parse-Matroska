use 5.008;
use strict;
use warnings;

package Parse::Matroska::Reader;
=head1 NAME

Parse::Matroska::Reader

=cut
use Parse::Matroska::Definitions qw{elem_by_hexid};
use Parse::Matroska::Element;

use Carp;
use Scalar::Util qw{openhandle weaken};
use IO::Handle;
use IO::File;
use List::Util qw{first};
use Encode;

=head1 SYNOPSIS

    use Parse::Matroska::Reader;
    my $reader = Parse::Matroska::Reader->new($path);
    $reader->close;
    $reader->open(\$string_with_matroska_data);

    my $elem = $reader->read_element;
    print "Element ID: $elem->{elid}\n";
    print "Element name: $elem->{name}\n";
    if ($elem->{type} ne 'sub') {
        print "Element value: $elem->get_value\n";
    } else {
        while (my $child = $elem->next_child) {
            print "Child element: $child->{name}\n";
        }
    }
    $reader->close;

=head1 DESCRIPTION

Reads EBML data, which is used in Matroska files.
This is a low-level reader which is meant to be used as a backend
for higher level readers. TODO: write the high level readers :)

=head1 NOTE

The API of this module is not yet considered stable.

=head1 METHODS

=over

=item new

Creates a new reader.
Calls L</open(arg)> with its arguments if provided.

=cut
sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;

    $self->open(@_) if @_;
    return $self;
}

=item open(arg)

Creates the internal filehandle. The argument can be:

=over

=item * An open filehandle or L<IO::Handle> object.
The filehandle is not C<dup()>ed, so calling L</close> in
this object will close the given filehandle as well.

=item * A scalar containing a path to a file.

=item * On perl v5.14 or newer, a scalarref pointing to
EBML data. For similar functionality in older perls,
give an L<IO::String> object.

=back

=cut
sub open {
    my ($self, $arg) = @_;
    $self->{fh} = openhandle($arg) || IO::File->new($arg, "<:raw")
        or croak "Can't open $arg: $!";
}

=item close

Closes the internal filehandle.

=cut
sub close {
    my ($self) = @_;
    $self->{fh}->close;
    delete $self->{fh};
}

# equivalent to $self->readlen(1), possibly faster
sub _getc {
    my ($self) = @_;
    my $c = $self->{fh}->getc;
    croak "Can't do read of length 1: $!" if !defined $c && $!;
    return $c;
}

=item readlen(length)

Reads C<length> bytes from the internal filehandle.

=cut
sub readlen {
    my ($self, $len) = @_;
    my $data;
    my $readlen = $self->{fh}->read($data, $len);
    croak "Can't do read of length $len: $!"
                 unless defined $readlen;
    return $data;
}

# converts a byte string into an integer
# we do so by converting the integer into a hex string (big-endian)
# and then reading the hex-string into an integer
sub _bin2int($) {
    my ($bin) = @_;
    # if the length is larger than 4
    # the resulting integer might be larger than INT_MAX
    if (length($bin) > 4) {
        use bigint try => 'GMP';
        return hex(unpack("H*", $bin));
    }
    return hex(unpack("H*", $bin));
}

# creates a floating-point number with the given mantissa and exponent
sub _ldexp {
    my ($mantissa, $exponent) = @_;
    return $mantissa * 2**$exponent;
}

# NOTE: the read_* functions are hard to read because they're ports
# of even harder to read python functions.
# TODO: make them readable

=item read_id

Reads an EBML ID atom in hexadecimal string format, suitable
for passing to L<Parse::Matroska::Definitions/elem_by_hexid>.

=cut
sub read_id {
    my ($self) = @_;
    my $t = $self->_getc;
    return undef unless defined $t;
    my $i = 0;
    my $mask = 1<<7;

    if (ord($t) == 0) {
        croak "Matroska Syntax error: first byte of ID was \\0"
    }
    until (ord($t) & $mask) {
        ++$i;
        $mask >>= 1;
    }
    # return hex string of the bytes we just read
    return unpack "H*", ($t . $self->readlen($i));
}

=item read_size

Reads an EBML Data Size atom, which immediately follows
an EBML ID atom.

This returns an array consisting of:

=over

=item 0 The length of the Data Size atom.

=item 1 The value encoded in the Data Size atom,
which is the length of all the data following it.

=back

=cut
sub read_size {
    my ($self) = @_;
    my $t = $self->_getc;
    my $i = 0;
    my $mask = 1<<7;

    if (ord($t) == 0) {
        croak "Matroska Syntax error: first byte of data size was \\0"
    }
    until (ord($t) & $mask) {
        ++$i;
        $mask >>= 1;
    }
    $t = $t & chr($mask-1); # strip length bits (keep only significant bits)
    return ($i+1, _bin2int $t . $self->readlen($i));
}

=item read_str(length)

Reads a string of length C<length> bytes from the internal filehandle.
The string is already L<Encode/decode>d from C<UTF-8>, which is the
standard Matroska string encoding.

=cut
{
    my $utf8 = find_encoding("UTF-8");
    sub read_str {
        my ($self, $length) = @_;
        return $utf8->decode($self->readlen($length));
    }
}

=item read_uint(length)

Reads an unsigned integer of length C<length> bytes
from the internal filehandle.

Returns a L<Math::BigInt> object if C<length> is greater
than 4.

=cut
sub read_uint {
    my ($self, $length) = @_;
    return _bin2int $self->readlen($length);
}

=item read_sint(length)

Reads a signed integer of length C<length> bytes
from the internal filehandle.

Returns a L<Math::BigInt> object if C<length> is greater
than 4.

=cut
sub read_sint {
    my ($self, $length) = @_;
    my $i = $self->read_uint($length);

    # Apply 2's complement to the unsigned int
    my $mask = int(2 ** ($length * 8 - 1));
    # if the most significant bit is set...
    if ($i & $mask) {
        # subtract the MSB twice
        $i -= 2 * $mask;
    }
    return $i;
}

=item read_float(length)

Reads an IEEE floating point number of length C<length>
bytes from the internal filehandle.

Only lengths '4' and '8' are supported (C 'float' and 'double').

=cut
sub read_float {
    my ($self, $length) = @_;
    my $i = $self->read_uint($length);
    my $f;

    # These evil expressions reinterpret an unsigned int as IEEE binary floats
    if ($length == 4) {
        $f = _ldexp(($i & (1<<23 - 1)) + (1<<23), ($i>>23 & (1<<8 - 1)) - 150);
        $f = -$f if $i & (1<<31);
    } elsif ($length == 8) {
        use bigrat try => 'GMP';
        $f = _ldexp(($i & (1<<52 - 1)) + (1<<52), ($i>>52 & (1<<12 - 1)) - 1075);
        $f = -$f if $i & (1<<63);
    } else {
        croak "Matroska Syntax error: unsupported IEEE float byte size $length";
    }

    return $f;
}

=item read_ebml_id(length)

Reads an EBML ID when it's encoded as the data inside
another EBML element, that is, when the enclosing element's
C<type> is "ebml_id".

This returns a hashref with the EBML element description as
defined in L<Parse::Matroska::Definitions>.

=cut
sub read_ebml_id {
    my ($self, $length) = @_;
    return elem_by_hexid(unpack("H*", $self->readlen($length)));
}

=item skip(length)

Skips C<length> bytes in the internal filehandle.

=cut
sub skip {
    my ($self, $len) = @_;
    return if $self->{fh}->can('seek') && $self->{fh}->seek($len, 1);
    $self->readlen($len);
    return;
}

=item getpos

Wrapper for L<IO::Seekable/$io-E<gt>getpos> in the internal filehandle.

Returns undef if the internal filehandle can't C<getpos>.

=cut
sub getpos {
    my ($self) = @_;
    return undef unless $self->{fh}->can('getpos');
    return $self->{fh}->getpos;
}

=item setpos(pos)

Wrapper for L<IO::Seekable/$io-E<gt>setpos> in the internal filehandle.

Returns undef if the internal filehandle can't C<setpos>.

Croaks if C<setpos> does not seek to the requested position,
that is, if calling C<getpos> does not yield the same object
as the C<pos> argument.

=cut
sub setpos {
    my ($self, $pos) = @_;
    return undef unless $pos && $self->{fh}->can('setpos');

    my $ret = $self->{fh}->setpos($pos);
    croak "Cannot seek to correct position"
        unless $self->getpos eq $pos;
    return $ret;
}

=item read_element(read_bin)

Reads a full EBML element from the internal filehandle.

Returns a L<Parse::Matroska::Element> initialized with the
read data. If C<read_bin> is not present or is false, will
delay-load the contents of 'binary' type elements, that is,
they will only be loaded when calling C<get_value> on the
returned L<Parse::Matroska::Element> object.

Does not read the children of the element if its type is
'sub'. Look into the L<Parse::Matroska::Element> interface
for details in how to read children elements.

Pass a true C<read_bin> if the stream being read is not
seekable (C<getpos> is undef) and the contents of 'binary'
elements is desired, otherwise seeking errors or
internal filehandle corruption might occur.

=cut
sub read_element {
    my ($self, $read_bin) = @_;
    return undef if $self->{fh}->eof;

    my $elem_pos = $self->getpos;

    my $elid = $self->read_id;
    my $elem_def = elem_by_hexid($elid);
    my ($size_len, $content_len) = $self->read_size;
    my $full_len = length($elid)/2 + $size_len + $content_len;

    my $elem = Parse::Matroska::Element->new(
        elid => $elid,
        name => $elem_def && $elem_def->{name},
        type => $elem_def && $elem_def->{valtype},
        size_len => $size_len,
        content_len => $content_len,
        full_len => $full_len,
        reader => $self,
        elem_pos => $elem_pos,
        data_pos => $self->getpos,
        );
    weaken($elem->{reader});

    if (defined $elem_def) {
        if ($elem->{type} eq 'sub') {
            $elem->{value} = [];
        } elsif ($elem->{type} eq 'str') {
            $elem->{value} = $self->read_str($content_len);
        } elsif ($elem->{type} eq 'ebml_id') {
            $elem->{value} = $self->read_ebml_id($content_len);
        } elsif ($elem->{type} eq 'uint') {
            $elem->{value} = $self->read_uint($content_len);
        } elsif ($elem->{type} eq 'sint') {
            $elem->{value} = $self->read_sint($content_len);
        } elsif ($elem->{type} eq 'float') {
            $elem->{value} = $self->read_float($content_len);
        } elsif ($elem->{type} eq 'skip') {
            $self->skip($content_len);
        } elsif ($elem->{type} eq 'binary') {
            if ($read_bin) {
                $elem->{value} = $self->readlen($content_len);
            } else {
                $self->skip($content_len);
            }
        } else {
            die "Matroska Definition error: type $elem->{valtype} unknown"
        }
    } else {
        $self->skip($content_len);
    }
    return $elem;
}

1;

=back

=head1 CAVEATS

Children elements have to be processed as soon as an element
with children is found, or their children ignored with
L<Parse::Matroska::Element/skip>. Not doing so doesn't cause
errors but results in an invalid structure, with constant '0'
depth.

To work correctly in unseekable streams, either the contents
of 'binary'-type elements has to be ignored or the C<read_bin>
flag to C<read_element> has to be true.

=head1 AUTHOR

Diogo Franco <diogomfranco@gmail.com>, aka Kovensky.
Initially based on a python script by Uoti Urpala.

=head1 SEE ALSO

L<Parse::Matroska::Definitions>, L<Parse::Matroska::Element>.

=head1 LICENSE

The FreeBSD license, equivalent to the ISC license.
