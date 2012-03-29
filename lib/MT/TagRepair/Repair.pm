package MT::TagRepair::Repair;

use strict;
use warnings;

use base qw( MT::TagRepair );

use MT::Log::Log4perl qw(l4mtdump); use Log::Log4perl qw( :resurrect );
###l4p our $logger = MT::Log::Log4perl->new();
# ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

sub class_label { 'Repair' }

sub execute {
    my $self = shift;
    $self->report_header( 'Starting Tag and ObjectTag repairs' );
    $self->SUPER::execute();
}

=head2 repair_tag_self_n8d

Repair tags returned by C<tag_self_n8d()>

=cut
sub repair_tag_self_n8d {
    my $self = shift;
    $self->report_header('Repairing self-referential normalization');

    my @tags;
    unless ( @tags = $self->tag_self_n8d() ) {
        $self->report('No tags found in repair_tag_self_n8d');
        return 0;
    }

    # Cache the tag data in memory
    $self->report(
        'Caching tag values for %d tags before removing them. ID(s): %s',
        scalar @tags,
        join(', ', map { $_->id } @tags )
    );
    my @tagdata = map { $_->column_values } @tags;

    # Remove the self_n8d tags
    $self->remove( @tags );

    my %replacement_id;
    foreach my $data ( @tagdata ) {

        # Get the original tag ID and remove it from the data hash
        my $old_id = delete $data->{id};

        # Discard the n8d_id since it was incorrect in the first place
        delete $data->{n8d_id};

        # Create and save a new tag with the old data (minus the tag_id)
        my $tag = MT::Tag->new();
        $tag->set_values( $data );
        $self->save( $tag );

        # Store the new tag ID in a hash, mapped to the old tag ID
        $replacement_id{$old_id} = $tag->id;
    }

    # Iteratively load all objecttags referencing the old tag IDs
    my $otag_iter
        = MT::ObjectTag->load_iter({ id => [ keys %replacement_id ] });

    # Modify each objecttag replacing the original tag_id value with the
    # replacement tag's ID
    while ( my $ot = $otag_iter->() ) {
        $ot->tag_id( $replacement_id{$ot->tag_id} );
        $self->save( $ot );
    }
}

=head2 repair_bad_n8d

Repair tags returned by C<tag_bad_n8d()>. The method returns an array of
array references where the first element in each array reference is a tag
object.

=cut
sub repair_bad_n8d {
    my $self = shift;
    $self->report_header('Repairing tags which incorrectly declare normalization');

    my @tags;
    unless ( @tags = $self->tag_bad_n8d() ) {
        $self->report('No tags found in repair_bad_n8d');
        return 0;
    }

    @tags = map { $_->[0]->n8d_id(0); shift @$_ } @tags;
    $self->save( @tags );
}

=head2 repair_no_n8d

Repair tags returned by C<tag_no_n8d()>

=cut
sub repair_no_n8d { 
    my $self = shift;
    $self->report_header('Repairing duplicate tags');

    my @tags;
    unless ( @tags = $self->tag_no_n8d() ) {
        $self->report('No tags found in repair_no_n8d');
        return 0;
    }

    $self->save( @tags );
}

=head2 repair_tag_dupes

Repairs duplicate tags which are returned from C<tag_dupes()> as array
references.

=cut
sub repair_tag_dupes {
    my $self = shift;
    $self->report_header('Repairing duplicate tags');

    my @tags;
    unless ( @tags = $self->tag_dupes() ) {
        $self->report('No tags found in repair_tag_dupes');
        return 0;
    }
    $self->repair_tag_dupe(@$_) foreach @tags;
}

=head2 repair_tag_dupe

Repair a single set of duplicate tags.  We do this by consolidating them into
the tag with the lowest ID (the canonical tag).

Because we're disabling callbacks, we have to adjust the ObjectTag records of
the duplicates to point to the canonical before removing the duplicate tag
objects.

=cut
sub repair_tag_dupe {
    my $self = shift;
    my (@tags) = @_;

    my ( $canon, @dupes ) = sort { $a->id <=> $b->id } @tags;

    return unless @dupes;

    $self->report('Repairing %s duplicates of tag "%s" (ID:%s)',
                    scalar @dupes, $canon->name, $canon->id );
    my @dupe_tag_ids = map { $_->id } @dupes;

    my $load_terms = {
        tag_id => ( @dupe_tag_ids > 1 ? \@dupe_tag_ids : $dupe_tag_ids[0] )
    };
    my $obj_tag_iter = MT::ObjectTag->load_iter( $load_terms )
        or $self->throw( load_error => 'MT::ObjectTag',
                         terms      => $load_terms,
                         fatal      => 1 );

    $self->report('Consolidating objecttag records for tag IDs: %s',
                    join(', ', @dupe_tag_ids) );
    while ( my $obj_tag = $obj_tag_iter->() ) {
        $self->report(
            'Altering tag_id value for objecttag ID %s from %s to %s',
            $obj_tag->id, $obj_tag->tag_id, $canon->id
        );
        $obj_tag->tag_id( $canon->id );
        $self->save( $obj_tag );
    }

    $load_terms = {
        n8d_id => ( @dupe_tag_ids > 1 ? \@dupe_tag_ids : $dupe_tag_ids[0] )
    };
    my $tag_iter = MT::Tag->load_iter( $load_terms )
        or $self->throw( load_error => 'MT::Tag',
                         terms      => $load_terms,
                         fatal      => 1 );

    $self->report('Redirecting tags referencing our dupe tags in their n8d_id for tag IDs: %s',
                    join(', ', @dupe_tag_ids) );
    while ( my $t = $tag_iter->() ) {
        $self->report(
            'Altering n8d_id value for tag ID %s from %s to %s',
            $t->id, $t->n8d_id, $canon->id
        );
        $t->n8d_id( $canon->id );
        $self->save( $t );
    }


    $self->remove( @dupes );
}

1;