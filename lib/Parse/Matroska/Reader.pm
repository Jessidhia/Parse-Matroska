use strict;
use warnings;

package Parse::Matroska::Reader;
use Parse::Matroska::Definitions qw{elem_by_hexid};
use Parse::Matroska::Element;

use Carp;
use Scalar::Util qw{openhandle weaken};
use IO::Handle;
use IO::File;
use List::Util qw{first};
use Encode;

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;

    $self->init(@_);
    return $self;
}

sub init {
    my ($self, $arg) = (@_);
    $self->{fh} = openhandle($arg) // IO::File->new($arg, "<:raw")
        or croak $!;
}

sub _getc {
    my ($self) = @_;
    my $c = $self->{fh}->getc;
    croak $! if !defined $c && $!;
    return $c;
}

sub readlen {
    my ($self, $len) = @_;
    my $data;
    my $readlen = $self->{fh}->read($data, $len);
    croak $!     unless defined $readlen;
    return undef unless $len == $readlen;
    return $data;
}

# converts a byte string into an integer
sub _bin2int($) {
    my ($bin) = @_;
    if (length($bin) > 7) {
        use bigint try => 'GMP';
        return hex(unpack("H*", $bin));
    }
    return hex(unpack("H*", $bin));
}

sub _ldexp {
    my ($mantissa, $exponent) = @_;
    return $mantissa * 2**$exponent;
}

# NOTE: the read_* functions are hard to read because they're ports
# of even harder to read python functions.
# TODO: make them readable

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

# returns (length of "data size", value of "data size")
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

{
    my $utf8 = find_encoding("UTF-8");
    sub read_str {
        my ($self, $length) = @_;
        return $utf8->decode($self->readlen($length));
    }
}

sub read_uint {
    my ($self, $length) = @_;
    return _bin2int $self->readlen($length);
}

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

sub read_ebml_id {
    my ($self, $length) = @_;
    return elem_by_hexid(unpack("H*", $self->readlen($length)));
}

sub skip {
    my ($self, $len) = @_;
    return if $self->{fh}->can('seek') && $self->{fh}->seek($len, 1);
    $self->readlen($len);
    return;
}

sub getpos {
    my ($self) = @_;
    return undef unless $self->{fh}->can('getpos');
    return $self->{fh}->getpos;
}

sub setpos {
    my ($self, $pos) = @_;
    return undef unless $pos && $self->{fh}->can('setpos');
    
    my $ret = $self->{fh}->setpos($pos);
    croak "Cannot seek to correct position"
        unless $self->getpos eq $pos;
    return $ret;
}

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