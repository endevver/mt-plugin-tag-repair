package MT::TagRepair;

=head1 NAME

MT::TagRepair - A repair object for corrupted MT::Tag objects

=cut
use strict;
use warnings;

use MT::Tag;
use MT::ObjectTag;
use Class::Accessor::Fast;

__PACKAGE__->mk_accessors(qw( verbose dryrun ));

=head1 METHODS

=cut

sub report {
    my $self = shift;
    my $msg  = shift;
    $ENV{TAGREPAIR_VERBOSE} and printf "$msg\n", @_;
}

sub report_header {
    $ENV{TAGREPAIR_VERBOSE} and shift()->report( "\n\n###### %s\n\n", shift());
}

###################### TAG SEARCH METHODS ######################

=head2 tag_dupes

Find all tags which have the same name (case-insensitive).

=cut
sub tag_dupes {
    my $self = shift;

    # Select tag names, grouped and ordered by number of tags with that name
    my $iter = MT::Tag->count_group_by(
        undef,
        {   group  => ['name'],
            binary => { name => 1 },     # Turns off case sensitivity
            sort   => [
                { column => 'count(*)', desc => 'DESC' },
                { column => 'name' }
            ]
        }
    );

    my @tag_groups = ();
    my %duped      = ();
    while ( my ( $count, $name ) = $iter->() ) {
        next unless $count > 1;         # Skip groups with only 1 tag (good!) 

        # Iterate through all tags with current $name
        foreach my $tag ( MT::Tag->load( { name => $name } )) {
            next if $duped{ $tag->name }++;

            # get the REAL count.
            # FIXME huh?  Why isn't $count "real"? NEEDS DOCUMENTATION
            my $true_count = MT::Tag->count(
                { name => $tag->name },
                { binary => { name => 1 } },    # Case-insensitive
            );

            next unless $true_count > 1;  # Skip name if only...errr...1 tag

            push @tag_groups,
                [
                MT::Tag->load(
                    { name   => $tag->name },
                    { binary => { name => 1 } }
                )
                ];
        }
    }
    @tag_groups;
}

=head2 tag_n8d

Find all tags where id and n8d_id are equal.  This should never happen.

=cut
sub tag_n8d { MT::Tag->load( { id => \'= tag_n8d_id' } ) }

=head2 tag_bad_n8d

Find all tags which declare another tag as its normalized version (n8d_id)
(i.e. not 0 and n8_id != id).  Look up the normalized tag to make sure it
exists AND it's correct.  If it doesn't, push it onto the return array as an
array reference with the normalized tag it currently and incorrectly points
to.

=cut
sub tag_bad_n8d {
    my $self = shift;
    my @bad_n8d = ();
    my $iter = MT::Tag->load_iter( { n8d_id => { not => '0' } } );
    while ( my $tag = $iter->() ) {

        # skip the self-normalized ones
        next if $tag->id == $tag->n8d_id;

        my $n8d_tag = MT::Tag->lookup( $tag->n8d_id );
        push @bad_n8d, [ $tag, $n8d_tag ]
            if !$n8d_tag
                || MT::Tag->normalize( $tag->name ) ne $n8d_tag->name;
    }

    @bad_n8d;
}

=head2 tag_no_n8d

Find all tags which declare themselves as the normalized version
(n8d_id = 0) but whose name isn't normalized.

=cut
sub tag_no_n8d {
    my $self = shift;
    my @no_n8d = ();
    my $iter = MT::Tag->load_iter( { n8d_id => '0' } );
    while ( my $tag = $iter->() ) {
        my $n8d = MT::Tag->normalize( $tag->name );
        push @no_n8d, $tag if $tag->name ne $n8d;
    }

    @no_n8d;
}

##################### REPAIR/SAVE METHODS ######################

=head2 save

This save method takes one or more MT::Object subclass instances and saves
them with MT callbacks disabled.  On error, the method dies with an
informative error message.

=cut
sub save {
    my $self = shift;
    my @objs = @_;
    local $MT::CallbacksEnabled = 0;
    foreach my $obj ( @objs ) {
        $self->report( 'Saving %s ID %d', lc($obj->class_label), $obj->id );
        next if $ENV{TAGREPAIR_DRYRUN};
        $obj->save
            or die sprintf "Error saving %s (ID:%d): %s",
                    lc($obj->class_label),
                    $obj->id,
                    ($obj->errstr||'UNKNOWN ERROR');
    }
}

=head2 repair_tag_n8d

Repair tags returned by C<tag_n8d()>

=cut
sub repair_tag_n8d {
    my $self = shift;
    $self->report_header('Repairing self-referential normalization');
    $self->save( $self->tag_n8d() )
}

=head2 repair_bad_n8d

Repair tags returned by C<tag_bad_n8d()>. The method returns an array of
array references where the first element in each array reference is a tag
object.

=cut
sub repair_bad_n8d {
    my $self = shift;
    $self->report_header('Repairing tags which incorrectly declare normalization');
    $self->save( map { $_->[0] } $self->tag_bad_n8d() );
}

=head2 repair_no_n8d

Repair tags returned by C<tag_no_n8d()>

=cut
sub repair_no_n8d { 
    my $self = shift;
    $self->report_header('Repairing duplicate tags');
    $self->save( $self->tag_no_n8d() ) }

=head2 repair_tag_dupes

Repairs duplicate tags which are returned from C<tag_dupes()> as array
references.

=cut
sub repair_tag_dupes {
    my $self = shift;
    $self->report_header('Repairing duplicate tags');
    $self->repair_tag_dupe(@$_) foreach $self->tag_dupes();
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

    my @dupe_tag_ids = map { $_->id } @dupes;
    {
        local $MT::CallbacksEnabled = 0;

        my $obj_tag_iter
            = MT::ObjectTag->load_iter( { tag_id => \@dupe_tag_ids } )
                or die "Could not load object tag (iter): "
                     . (MT::ObjectTag->errstr||'UNKNOWN ERROR');

        $self->report('Consolidating objecttag records for tag IDs: %d',
                        join(', ', @dupe_tag_ids) );
        while ( my $obj_tag = $obj_tag_iter->() ) {
            $self->report(
                'Altering tag_id value for objecttag %d from %d to %d',
                $obj_tag->id, $obj_tag->tag_id, $canon->id
            );
            $obj_tag->tag_id( $canon->id );
            $self->save( $obj_tag );
        }

        $self->report( 'Removing MT::Tag records: %s',
                        join(', ', @dupe_tag_ids) );
        next if $ENV{TAGREPAIR_DRYRUN};
        unless ( MT::Tag->remove( { id => \@dupe_tag_ids } ) ) {
            warn sprintf "Error removing MT::Tag record(s): %s. %s",
                join(', ', @dupe_tag_ids), (MT::Tag->errstr||'UNKNOWN ERROR')
        }
    }
}

1;
