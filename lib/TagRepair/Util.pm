package TagRepair::Util;

use strict;
use warnings;

use MT::Tag;
use MT::ObjectTag;

##################### REPAIR/SAVE METHODS ######################

sub save {
    my $self = shift;
    my @objs = @_;
    local $MT::CallbacksEnabled = 0;
    foreach my $obj ( @objs ) {
        $_->save
            or die sprintf "Error saving %s (ID:%d): %s",
                    lc($obj->class_label),
                    $obj->id,
                    ($obj->errstr||'UNKNOWN ERROR');
    }
}

sub repair_tag_n8d { $_[0]->save( $_[0]->tag_n8d() ) }

sub repair_bad_n8d {
    my $self = shift;
    $self->save( map { $_->[0] } $self->tag_bad_n8d() );
}

sub repair_no_n8d { $_[0]->save( $_[0]->tag_no_n8d() ) }

sub repair_tag_dupes {
    my $self = shift;
    $self->repair_tag_dupe(@$_) foreach $self->tag_dupes();
}

sub repair_tag_dupe {
    my $self = shift;
    my (@tags) = @_;

    # The tag with the lowest id (i.e. the *first* one) will be canonical
    my ( $canon, @dupes ) = sort { $a->id <=> $b->id } @tags;

    # Find and modify objecttag records referencing the dupe tags to
    # so that they reference the canonical tag instead. Once complete
    # remove the dupe tags altogether.
    my @dupe_tag_ids = map { $_->id } @dupes;
    {
        # nix callbacks for the following operations
        local $MT::CallbacksEnabled = 0;

        my $obj_tag_iter
            = MT::ObjectTag->load_iter( { tag_id => \@dupe_tag_ids } )
                or die "Could not load object tag (iter): "
                     . (MT::ObjectTag->errstr||'UNKNOWN ERROR');

        while ( my $obj_tag = $obj_tag_iter->() ) {
            $obj_tag->tag_id( $canon->id );
            $self->save( $obj_tag );
        }

        # kill the bad tags
        unless ( MT::Tag->remove( { id => \@dupe_tag_ids } ) ) {
            warn sprintf "Error removing MT::Tag records: %s. %s",
                join(', ', @dupe_tag_ids), (MT::Tag->errstr||'UNKNOWN ERROR')
        }
    }
}


######################### LOAD METHODS #########################

sub tag_dupes {
    my $self = shift;
    my $iter = MT::Tag->count_group_by(
        undef,
        {   group  => ['name'],
            binary => { name => 1 },
            sort   => [
                { column => 'count(*)', desc => 'DESC' },
                { column => 'name' }
            ]
        }
    );
    my @tag_groups = ();
    my %duped      = ();
    while ( my ( $count, $name ) = $iter->() ) {
        next unless $count > 1;

        # check for other potential dupes
        # use a non-binary search to get all the combos
        my @potential_dupes = MT::Tag->load( { name => $name } );
        foreach my $tag (@potential_dupes) {
            next if $duped{ $tag->name }++;

            # get the REAL count
            my $true_count = MT::Tag->count( { name => $tag->name },
                { binary => { name => 1 } } );
            next unless $true_count > 1;
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

sub tag_n8d { MT::Tag->load( { id => \'= tag_n8d_id' } ) }

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

1;
