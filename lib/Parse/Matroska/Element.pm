use strict;
use warnings;

package Parse::Matroska::Element;

use Carp;
use List::Util qw{first};

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;

    $self->initialize(@_);
    return $self;
}

sub initialize {
    my ($self, %args) = @_;
    for (keys %args) {
        $self->{$_} = $args{$_};
    }
    $self->{depth} //= 0;
}

sub skip {
    my ($self) = @_;
    my $reader = $self->{reader};
    return unless $reader; # we don't have to skip if there's no reader
    my $pos = $reader->getpos;
    croak "Too late to skip, reads were already done"
        if $pos ne $self->{data_pos};
    $reader->skip($self->{content_len});
}

# the optional second parameter will keep the value
# of 'binary' fields in $self->{value}.
sub get_value {
    my ($self, $keep_bin) = @_;

    return undef if $self->{type} eq 'skip';
    return $self->{value} if $self->{value};


    my $reader = $self->{reader} or
        croak "The associated Reader has been deleted";

    # delay-loaded 'binary'
    if ($self->{type} eq 'binary') {
        croak "Cannot seek in the current Reader" unless $self->{data_pos};
        # seek to the data position...
        $reader->setpos($self->{data_pos});
        # read the data, keeping it in value if requested
        if ($keep_bin) {
            $self->{value} = $reader->readlen($self->{content_len});
            return $self->{value};
        } else {
            return $reader->readlen($self->{content_len});
        }
    }
}

# Builtin iterator;
# optional parameter has new elements loaded from disk
# also read their 'binary' data
sub next_child {
    my ($self, $read_bin) = @_;
    return unless $self->{type} eq 'sub';

    if ($self->{_all_children_read}) {
        my $idx = $self->{_last_child} //= 0;
        if ($idx == @{$self->{value}}) {
            # reset the iterator, returning undef once
            $self->{_last_child} = 0;
            return;
        }
        my $ret = $self->{value}->[$idx];

        ++$idx;
        $self->{_last_child} = $idx;
        return $ret;
    }

    my $len = $self->{remaining_len} // $self->{content_len};

    if ($len == 0) {
        # we've read all children; switch into $self->{value} iteration mode
        $self->{_all_children_read} = 1;
        # return undef since the iterator will reset
        return;
    }

    $self->{pos_offset} //= 0;
    my $pos = $self->{data_pos};
    my $reader = $self->{reader} or croak "The associated reader has been deleted";
    $reader->setpos($pos);
    $reader->{fh}->seek($self->{pos_offset}, 1) if $pos;

    my $chld = $reader->read_element($read_bin);
    return undef unless defined $chld;
    $self->{pos_offset} += $chld->{full_len};

    $self->{remaining_len} = $len - $chld->{full_len};

    if ($self->{remaining_len} < 0) {
        croak "Child elements consumed $self->{remaining_len} more bytes than parent $self->{name} contained";
    }

    $chld->{depth} = $self->{depth} + 1;
    $self->{value} //= [];

    push @{$self->{value}}, $chld;

    return $chld;
}

sub all_children {
    my ($self, $recurse, $read_bin) = @_;
    $self->populate_children($recurse, $read_bin);
    return $self->{value};
}

sub children_by_name {
    my ($self, $name) = @_;
    my $ret = [grep { $_->{name} eq $name } @{$self->{value}}];
    return unless @$ret;
    return $ret->[0] if @$ret == 1;
    return $ret;
}

# calling populate_children(1,1) on the very first element read
# should load the entire file into memory and eliminate seeks
sub populate_children {
    my ($self, $recurse, $read_bin) = @_;

    return unless $self->{type} eq 'sub';

    if (@{$self->{value}} && $recurse) {
        # only recurse
        foreach (@{$self->{value}}) {
            $_->populate_children($recurse, $read_bin);
        }
        return @{$self->{value}};
    }

    while (my $chld = $self->next_child($read_bin)) {
        $chld->populate_children($recurse, $read_bin) if $recurse;
    }

    return @{$self->{value}};
}

1;
