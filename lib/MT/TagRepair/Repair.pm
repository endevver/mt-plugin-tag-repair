package MT::TagRepair::Repair;

use strict;
use warnings;

use base qw( MT::TagRepair );
use Data::Dumper;
use MT::Log::Log4perl qw(l4mtdump); use Log::Log4perl qw( :resurrect );
###l4p our $logger = MT::Log::Log4perl->new();
# ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();


sub class_label { 'Repair' }

# FIXME tagrepair --dryrun yields no output

sub execute { shift()->SUPER::execute() }

=head2 save

This method takes a single MT::Object subclass instance or an array of them
and saves them to the database.  On error, the method dies with an
informative error message.

Because the work performed by the plugin is so intensive, callbacks are
diabled globally during the save to prevent any harmful conflicts or interactions with other third-party plugins (e.g. Pusherman would have a
China Syndrom-style meltdown).

Furthermore, to route around some bad assumptions and lazy programming in
<MT::Tag::save> which was complicit in persisting (if not causing) the
problem, we save the tags via save method in C<MT::Tag>'s base class,
C<MT::Object>.

=cut
sub save {
    my $self = shift;
    my @objs = @_;
    local $MT::CallbacksEnabled = 0;
    foreach my $obj ( @objs ) {  # Objects may not be the same type
        my $meth = $self->can('_save_' .$obj->datasource ) || "_save";
        $self->$meth( $obj );
    }
}

sub _save_tag {
    my $self   = shift;
    my $tag    = shift;
    my $n8d_id = $tag->n8d_id;
    my $n8d    = $self->load( MT->model('tag'), $n8d_id ) if $n8d_id;
    my $is_n8d = defined($n8d_id) && $n8d_id == 0;

    $self->report([ '- Saving %s with %s', 
                     $self->tag_desc($tag),
                     (   $n8d    ? 'n8d ' . $self->tag_desc($n8d)
                       : $is_n8d ? 'n8d form'
                       : $n8d_id ? "unloadable n8d tag (ID:$n8d_id)"
                                 : 'undefined n8d_id'               )]);

    unless ( $self->dryrun ) {
        my $save = $self->{no_super_save} ? MT::Tag->can('save')
                                          : MT::Object->can('save');
        $tag->$save() or $self->throw( save_error => $tag );
    }
}

sub _save_objecttag {
    my $self  = shift;
    my $otag  = shift;

    $self->report([
        $otag->id ? ( '- Saving objecttag ID %d',  $otag->id )
                  : ( '- Saving new objecttag %s', Dumper($otag->column_values))
    ]);
    
    unless ( $self->dryrun ) {

        # print '$MT::DebugMode & 4 = '.($MT::DebugMode & 4)."\n";
        $self->debug([
            'BEFORE SAVE changed_cols: %s. %s',
                join(', ', keys %{ $otag->{changed_cols} }),
                Dumper($otag)
        ]);

        # Debugging... Ignore....
        # local $ENV{DOD_DEBUG} = 1;
        # local $Data::ObjectDriver::DEBUG = 1;
        # Data::ObjectDriver->logger(sub { $self->output(@_) });
        # local $ENV{DOD_PROFILE} = 1;

        $otag->save or $self->throw( save_error => $otag );

        $self->debug( 'AFTER SAVE: '. Dumper($otag));
    }
}


=head2 remove

This remove method takes one or more MT::Object subclass instances and removes
them with MT callbacks disabled.  On error, the method dies with an
informative error message.

=cut
sub remove {
    my $self = shift;
    my @objs = @_;
    local $MT::CallbacksEnabled = 0;

    foreach my $obj ( @objs ) {
        $self->report([ '- Removing %s ID %s', lc( $obj->class_label ), $obj->id]);
        unless ( $self->dryrun ) {
            my @obj_data
                = ( $obj->datasource, $self->dump1l( $obj->column_values() ));

            $obj->remove or $self->throw( remove_error => $obj );

            $self->debug([ '- REMOVED %s %s', @obj_data ]);
        }
    }
}

=head2 repair_self_n8d

Repair tags returned by C<tag_self_n8d()>

=cut
sub repair_self_n8d {
    my $self = shift;
    my $tag_cnt = my @tags = $self->tag_self_n8d();

    $self->start_phase(
        'Repairing self-referential normalization' =>
            ( $tag_cnt ? "$tag_cnt tags are" : 'No tags found' )
            . ' in this state'
    );

    return $self->end_phase() unless @tags;  # FIXME

    my %tags = map { $_->id => $_ } @tags;

    $self->report([
         '- Temporarily caching tag data for and removing '
        .'%d self-normalized tags: ID(s): %s',
        scalar @tags, join(', ', keys %tags )
    ]);

    $self->indent();

    my @tagdata;
    foreach my $tag_id ( keys %tags ) {
        my $tag = $tags{$tag_id};

        # Cache the tag data in memory
        $self->report([ '- Cached values for tag "%s" (ID:%d)',
                        $tag->name, $tag_id ]);
        push( @tagdata, $tag->column_values );

        # Remove the self_n8d tags
        $self->remove( $tag );
    }

    $self->outdent();

    $self->report( '- Now creating/saving new tags for each of the above '
                  .'with new, higher tag ID and properly discovered n8d_id');

    $self->indent();
    my %replacement_id;
    foreach my $data ( @tagdata ) {

        # Get the original tag ID and remove it from the data hash
        my $old_id = delete $data->{id};

        # Discard the n8d_id since it was incorrect in the first place
        delete $data->{n8d_id};

        # Create and save a new tag with the old data (minus the tag_id)
        my $tag = MT::Tag->new();
        $tag->set_values( $data );
        local $self->{no_super_save} = 1;
        $self->save( $tag );

        # Store the new tag ID in a hash, mapped to the old tag ID
        $replacement_id{$old_id} = $tag->id;
    }
    $self->outdent();

    $self->report( '- Repairing tag_id reference for objecttags which '
                  .'referred to the above, deleted tags' );

    $self->indent();
    # Iteratively load all objecttags referencing the old tag IDs
    my $otag_iter
        = MT::ObjectTag->load_iter({ id => [ keys %replacement_id ] });

    # Modify each objecttag replacing the original tag_id value with the
    # replacement tag's ID
    while ( my $ot = $otag_iter->() ) {
        $ot->tag_id( $replacement_id{$ot->tag_id} );
        $self->save( $ot );
    }
    $self->outdent();

    $self->end_phase();
}

=head2 repair_bad_n8d

Repair tags returned by C<tag_bad_n8d()>. The method returns an array of
array references where the first element in each array reference is a tag
object.

=cut
sub repair_bad_n8d {
    my $self    = shift;
    my $tag_cnt = my @tagsets = $self->tag_bad_n8d();

    $self->start_phase(
        'Repairing incorrect normalization references' =>
            ( @tagsets ? "$tag_cnt tags are" : 'No tags found' )
            . ' in this state'
    );

    return $self->end_phase() unless @tagsets;   # FIXME

    my @tags;
    foreach ( @tagsets ) {
        my $tag = shift @$_;
        my $n8d = 
            $self->load( 'MT::Tag', { name => $tag->normalize        },
                                    { $self->CASE_SENSITIVE_LOAD() }, );

        my $old_n8d = $tag->n8d_id;
        $tag->n8d_id(
            $n8d && $n8d->id < $tag->id  ? $n8d->id    # Fix it!
                                         : $tag->id    # Push to self_n8d
        );

        $self->report([ '- Changed tag ID %d n8d_id from %d to %d',
                        $tag->id, $old_n8d, $tag->n8d_id ]);

        $self->save( $tag );
    }


    $self->end_phase();
}

=head2 repair_no_n8d

Repair tags returned by C<tag_no_n8d()>

=cut
sub repair_no_n8d {
    my $self = shift;
    my $tag_cnt = my @tags = $self->tag_no_n8d();

    $self->start_phase(
        'Repairing false normalization declarations' =>
            ( @tags ? "$tag_cnt tags are" : 'No tags found' )
            . ' in this state which we\'re temporarily self-normalizing'
    );

    foreach my $tag ( @tags ) {
        my $old_n8d_id = $tag->n8d_id;

        $self->report([
            '- Changed tag ID %s n8d_id from %s to %s',
            $tag->id, $tag->n8d_id, $tag->id
        ]);
        $tag->n8d_id( $tag->id );   # Push to self_n8d

        $self->save( $tag );
    }

    $self->end_phase();
}

=head2 repair_tag_dupes

Repairs duplicate tags which are returned from C<tag_dupes()> as array
references.

=cut
sub repair_tag_dupes {
    my $self    = shift;
    my $tag_cnt = my @tags = $self->tag_dupes();

    $self->start_phase(
        'Repairing duplicate tags' =>
            ( @tags ? "$tag_cnt tags are" : 'No tags found' )
            . ' in this state'
    );

    $self->repair_tag_dupe(@$_) foreach @tags;

    $self->end_phase();
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

    my @dupe_tag_ids = map { $_->id } @dupes;

    $self->report([ 'Repairing %s duplicate(s) of tag "%s" (ID:%s): %s',
                    scalar @dupes, 
                    $canon->name, 
                    $canon->id, 
                    join(', ', @dupe_tag_ids),
                ]);

    my $load_terms = {
        tag_id => ( @dupe_tag_ids > 1 ? \@dupe_tag_ids : $dupe_tag_ids[0] )
    };

    my $obj_tag_iter = MT::ObjectTag->load_iter( $load_terms )
        or $self->throw( load_error => 'MT::ObjectTag',
                         terms      => $load_terms,
                         fatal      => 1 );

    $self->indent();
    $self->report('- Consolidating objecttag records');

    $self->indent();
    while ( my $obj_tag = $obj_tag_iter->() ) {
        $self->report([
            '- Changed objecttag ID %s tag_id from %s to %s',
            $obj_tag->id, $obj_tag->tag_id, $canon->id
        ]);
        $obj_tag->tag_id( $canon->id );
        $self->save( $obj_tag );
    }
    $self->outdent();
    $self->outdent();

    $load_terms = {
        n8d_id => ( @dupe_tag_ids > 1 ? \@dupe_tag_ids : $dupe_tag_ids[0] )
    };
    my $tag_iter = MT::Tag->load_iter( $load_terms )
        or $self->throw( load_error => 'MT::Tag',
                         terms      => $load_terms,
                         fatal      => 1 );

    $self->indent();
    $self->report( '- Consolidating normalized tag references' );

    $self->indent();
    while ( my $t = $tag_iter->() ) {
        $self->report([
            '- Changed %s ID %s %s from %s to %s',
            'tag', $t->id, 'n8d_id', $t->n8d_id, $canon->id
        ]);
        $t->n8d_id( $canon->id );
        $self->save( $t );
    }
    $self->outdent();

    $self->remove( @dupes );

    $self->outdent();
}

1;
