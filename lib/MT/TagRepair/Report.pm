package MT::TagRepair::Report;

use strict;
use warnings;

use base qw( MT::TagRepair );

use MT::Log::Log4perl qw(l4mtdump); use Log::Log4perl qw( :resurrect );
###l4p our $logger = MT::Log::Log4perl->new();
# ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

sub class_label { 'Report' }

sub execute { shift()->SUPER::execute() }

sub report_tag_dupes {
    my $self = shift;
    my $cnt = my @tags = $self->tag_dupes;

    $self->report_header(
        'Duplicate tags' =>
            (
                @tags  ?    'The following is a list of tag names which '
                          . 'are in use by more than one tag using the '
                          . 'identical case.'
                       :  '  NO TAGS FOUND IN THIS STATE!!'
            )
    );

    if ( @tags and $self->verbose ) {

        $self->report([ '%-11s %-20s %s',
                        '# of tags', 'Tag IDs', 'Duplicated tag names' ]);

        foreach my $tagset ( @tags ) {
            my $name    = $tagset->[0]->name;
            my $tag_cnt = scalar @$tagset;
            my $tag_ids = join( ', ', map { $_->id } @$tagset );
            $self->report([ '   %-8d %-20s %s',
                            $tag_cnt, $tag_ids, $name ]);
        }
    }

    unless ( $self->verbose and ! @tags ) {
        my $dupe_count = 0;
        $dupe_count += scalar @$_ - 1 foreach @tags;

        $self->output([ '%d duplicate tags (%d duped names).',
                            $dupe_count, $cnt ]);
    }
}

sub report_self_n8d {
    my $self = shift;
    my $cnt  = my @tags = $self->tag_self_n8d;

    $self->report_header(
        'Self-referential normalization' =>
            (
                @tags  ?    'The following tags have identical ID and '
                          . 'n8d_id values which should never happen '
                          . 'and can cause undefined behaviors'
                       :  '  NO TAGS FOUND IN THIS STATE!!'
            )
    );

    if ( @tags and $self->verbose ) {
        $self->report([ "  %-10s %s", 'Tag ID', 'Name']);
        $self->report([ "  %-10d %s", $_->id, $_->name ])
            foreach @tags;
    }

    $self->output(
        "$cnt tag(s) have a self-referential normalized tag reference.")
      if @tags or ! $self->verbose;
}

sub report_bad_n8d {
    my $self = shift;
    my $cnt  = my @tags = $self->tag_bad_n8d;

    $self->report_header(
        'Incorrect normalization references' =>
            (
                @tags  ?    'The following $cnt tags refer to a normalized '
                          . 'tag that either does not exist or is completely '
                          . 'unrelated and dissimilar'
                       :  '  NO TAGS FOUND IN THIS STATE!!'
            )
    );


    if ( @tags and $self->verbose ) {
        $self->report([ '  %-7s %-42s    %-7s %s',
                       'Tag ID', 'Tag Name', 'N8d ID', 'N8d Tag Name' ]);
        foreach my $tags (@tags) {
            my ( $tag, $n8d ) = @$tags;
            $self->report([
                '  %-7d %-45s %-7d %s',
                $tag->id, $tag->name,
                ( $n8d  ? ($n8d->id, $n8d->name) 
                        : ('n/a', 'a non-existant tag') )
            ]);
        }
    }

    $self->output(
        "$cnt tags(s) reference a non-existent or incorrect normalized tag.")
      if @tags or ! $self->verbose;
}

sub report_no_n8d {
    my $self = shift;
    my $cnt  = my @tags = $self->tag_no_n8d;

    $self->report_header(
        'False declaration of normalization' =>
            (
                @tags ?   "The following $cnt tags falsely claim to"
                        . 'be the normalized form.'
                      : '  NO TAGS FOUND IN THIS STATE!!'
            )
    );

    if ( @tags && $self->verbose ) {
        $self->report([ "  %-10s %s", 'Tag ID', 'Name' ]);
        $self->report([ "  %-10d %s", $_->id, $_->name ])
            foreach @tags;
    }

    $self->output(
        "$cnt false normalized form declarations by non-normalized tag(s).")
      if @tags or ! $self->verbose;
}


1;