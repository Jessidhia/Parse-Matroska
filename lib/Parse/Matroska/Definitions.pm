use common::sense;
package Parse::Matroska::Definitions;

use Parse::Matroska::Utils qw{uniq uncamelize};

use Exporter;
our @ISA       = qw{Exporter};
our @EXPORT_OK = qw{elem_by_hexid %EBML_DEFINITION %MATROSKA_DEFINITION};

@Parse::Matroska::Definitions::global_elem_list = ();
%Parse::Matroska::Definitions::global_elem_dict = ();

our %EBML_DEFINITION = define_ebml();
our %MATROSKA_DEFINITION = define_matroska();

sub elem_by_hexid {
    my ($elid) = @_;
    return $Parse::Matroska::Definitions::global_elem_dict{$elid};
}

################################################
### Helper functions for document definition ###
################################################

# used by elem when setting the 'valname' key
use constant TYPE_MAP => {
    uint    => 'uint64_t',
    str     => 'struct bstr',
    binary  => 'struct bstr',
    ebml_id => 'uint32_t',
    float   => 'double',
    sint    => 'int64_t',
};

# this will be localized to "MATROSKA" or "EBML" on the elem declarations
our $ELEM_DEFINE_TYPE = undef;

# Bakes a hash with:
# name        => $_[0]; the ebml element name
# elid        => $_[1]; the ebml hex id
# valtype     => $_[2]; the ebml type, lowercase... or an arrayref to set subelements
# multiple    => if name has a * at the end, set as true (used for repeating elements)
# definename  => the name used in the generated #defines
# fieldname   => the name used when present as a field in generated structs
# structname  => the name used when declaring a struct for this element
# subelements => arrayref of subelements, given through $_[2]; also sets valtype to sub.
# subids      => set of the ebml hex ids of the subelements
# ebmltype    => a pre#defined constant to describe the element's type, set from valtype
# valname     => typename used when declaring a struct field referring to this element
sub elem {
    my %e = (name => shift, elid => shift, valtype => shift);

    # strip * from name, set 'multiple' if there was one
    $e{multiple} = scalar $e{name} =~ s/\*$//;

    # ELEM_DEFINE_TYPE is either MATROSKA or EBML
    $e{definename} = "${ELEM_DEFINE_TYPE}_ID_".uc($e{name});
    $e{fieldname} = uncamelize $e{name};
    $e{structname} = "ebml_$e{fieldname}";

    if (ref $e{valtype} eq 'HASH') {
        $e{subelements} = $e{valtype};
        $e{subids} = uniq map { $_->{elid} } values %{$e{subelements}};
        $e{valtype} = 'sub';
        $e{ebmltype} = 'EBML_TYPE_SUBELEMENTS';
        $e{valname} = "struct $e{structname}";
    } else {
        $e{ebmltype} = "EBML_TYPE_\U$e{valtype}";
        die "Unrecognized value type $e{valtype}" unless
            defined ($e{valname} = TYPE_MAP->{$e{valtype}});
    }
    my $e = \%e;
    push @Parse::Matroska::Definitions::global_elem_list, $e;
    $Parse::Matroska::Definitions::global_elem_dict{$e{elid}} = $e;
    return ($e{elid}, $e);
}

#############################################
### EBML and Matroska document definitons ###
#############################################

sub define_ebml {
    local $ELEM_DEFINE_TYPE = 'EBML';
    return (
        elem('EBML', '1a45dfa3', {
            elem('EBMLVersion',        '4286', 'uint'),
            elem('EBMLReadVersion',    '42f7', 'uint'),
            elem('EBMLMaxIDLength',    '42f2', 'uint'),
            elem('EBMLMaxSizeLength',  '42f3', 'uint'),
            elem('DocType',            '4282', 'str'),
            elem('DocTypeVersion',     '4287', 'uint'),
            elem('DocTypeReadVersion', '4285', 'uint'),
        }),

        elem('CRC32',      'bf', 'binary'),
        elem('Void',       'ec', 'binary'),
    );
}

sub define_matroska {
    local $ELEM_DEFINE_TYPE = 'MATROSKA';
    return (
        elem('Segment', '18538067', {
            elem('SeekHead*', '114d9b74', {
                elem('Seek*', '4dbb', {
                    elem('SeekID',       '53ab', 'ebml_id'),
                    elem('SeekPosition', '53ac', 'uint'),
                }),
            }),

            elem('Info*', '1549a966', {
                elem('SegmentUID',      '73a4', 'binary'),
                elem('PrevUID',       '3cb923', 'binary'),
                elem('NextUID',       '3eb923', 'binary'),
                elem('TimecodeScale', '2ad7b1', 'uint'),
                elem('DateUTC',         '4461', 'sint'),
                elem('Title',           '7ba9', 'str'),
                elem('MuxingApp',       '4d80', 'str'),
                elem('WritingApp',      '5741', 'str'),
                elem('Duration',        '4489', 'float'),
            }),

            elem('Cluster*', '1f43b675', {
                elem('Timecode', 'e7', 'uint'),
                elem('BlockGroup*', 'a0', {
                    elem('Block',           'a1', 'binary'),
                    elem('BlockDuration',   '9b', 'uint'),
                    elem('ReferenceBlock*', 'fb', 'sint'),
                }),
                elem('SimpleBlock*', 'a3', 'binary'),
            }),

            elem('Tracks*', '1654ae6b', {
                elem('TrackEntry*', 'ae', {
                    elem('TrackNumber',            'd7', 'uint'),
                    elem('TrackUID',             '73c5', 'uint'),
                    elem('TrackType',              '83', 'uint'),
                    elem('FlagEnabled',            'b9', 'uint'),
                    elem('FlagDefault',            '88', 'uint'),
                    elem('FlagForced',           '55aa', 'uint'),
                    elem('FlagLacing',             '9c', 'uint'),
                    elem('MinCache',             '6de7', 'uint'),
                    elem('MaxCache',             '6df8', 'uint'),
                    elem('DefaultDuration',    '23e383', 'uint'),
                    elem('TrackTimecodeScale', '23314f', 'float'),
                    elem('MaxBlockAdditionID',   '55ee', 'uint'),
                    elem('Name',                 '536e', 'str'),
                    elem('Language',           '22b59c', 'str'),
                    elem('CodecID',                '86', 'str'),
                    elem('CodecPrivate',         '63a2', 'binary'),
                    elem('CodecName',          '258688', 'str'),
                    elem('CodecDecodeAll',         'aa', 'uint'),
                    elem('Video', 'e0', {
                        elem('FlagInterlaced',  '9a', 'uint'),
                        elem('PixelWidth',      'b0', 'uint'),
                        elem('PixelHeight',     'ba', 'uint'),
                        elem('DisplayWidth',  '54b0', 'uint'),
                        elem('DisplayHeight', '54ba', 'uint'),
                        elem('DisplayUnit',   '54b2', 'uint'),
                        elem('FrameRate',   '2383e3', 'float'),
                    }),
                    elem('Audio', 'e1', {
                        elem('SamplingFrequency',         'b5', 'float'),
                        elem('OutputSamplingFrequency', '78b5', 'float'),
                        elem('Channels',                  '9f', 'uint'),
                        elem('BitDepth',                '6264', 'uint'),
                    }),
                    elem('ContentEncodings', '6d80', {
                        elem('ContentEncoding*', '6240', {
                            elem('ContentEncodingOrder', '5031', 'uint'),
                            elem('ContentEncodingScope', '5032', 'uint'),
                            elem('ContentEncodingType',  '5033', 'uint'),
                            elem('ContentCompression', '5034', {
                                elem('ContentCompAlgo',     '4254', 'uint'),
                                elem('ContentCompSettings', '4255', 'binary'),
                            }),
                        }),
                    }),
                }),
            }),

            elem('Cues', '1c53bb6b', {
                elem('CuePoint*', 'bb', {
                    elem('CueTime', 'b3', 'uint'),
                    elem('CueTrackPositions*', 'b7', {
                        elem('CueTrack',           'f7', 'uint'),
                        elem('CueClusterPosition', 'f1', 'uint'),
                    }),
                }),
            }),

            elem('Attachments', '1941a469', {
                elem('AttachedFile*', '61a7', {
                    elem('FileDescription', '467e', 'str'),
                    elem('FileName',        '466e', 'str'),
                    elem('FileMimeType',    '4660', 'str'),
                    elem('FileData',        '465c', 'binary'),
                    elem('FileUID',         '46ae', 'uint'),
                }),
            }),

            elem('Chapters', '1043a770', {
                elem('EditionEntry*', '45b9', {
                    elem('EditionUID',         '45bc', 'uint'),
                    elem('EditionFlagHidden',  '45bd', 'uint'),
                    elem('EditionFlagDefault', '45db', 'uint'),
                    elem('EditionFlagOrdered', '45dd', 'uint'),
                    elem('ChapterAtom*', 'b6', {
                        elem('ChapterUID',               '73c4', 'uint'),
                        elem('ChapterTimeStart',           '91', 'uint'),
                        elem('ChapterTimeEnd',             '92', 'uint'),
                        elem('ChapterFlagHidden',          '98', 'uint'),
                        elem('ChapterFlagEnabled',       '4598', 'uint'),
                        elem('ChapterSegmentUID',        '6e67', 'binary'),
                        elem('ChapterSegmentEditionUID', '6ebc', 'uint'),
                        elem('ChapterDisplay*', '80', {
                            elem('ChapString',      '85', 'str'),
                            elem('ChapLanguage*', '437c', 'str'),
                            elem('ChapCountry*',  '437e', 'str'),
                        }),
                    }),
                }),
            }),
            elem('Tags*', '1254c367', {
                elem('Tag*', '7373', {
                    elem('Targets', '63c0', {
                        elem('TargetTypeValue',     '68ca', 'uint'),
                        elem('TargetTrackUID',      '63c5', 'uint'),
                        elem('TargetEditionUID',    '63c9', 'uint'),
                        elem('TargetChapterUID',    '63c4', 'uint'),
                        elem('TargetAttachmentUID', '63c6', 'uint'),
                     }),
                    elem('SimpleTag*', '67c8', {
                        elem('TagName',     '45a3', 'str'),
                        elem('TagLanguage', '447a', 'str'),
                        elem('TagString',   '4487', 'str'),
                    }),
                }),
            }),
        }),
    );
}

1;