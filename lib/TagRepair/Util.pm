package TagRepair::Util;

use strict;
use warnings;

use MT::Tag;
use MT::ObjectTag;

sub tag_dupes {

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

sub repair_tag_dupe {
    my (@duped_tags) = @_;

    # pick a tag with the lowest id (i.e. the *first* one)
    @duped_tags = sort { $a->id <=> $b->id } @duped_tags;

    {

        # nix callbacks
        local $MT::CallbacksEnabled = 0;

        # find the tag records (i.e. object tags)
        my $good_tag = shift @duped_tags;
        my @bad_ids = map { $_->id } @duped_tags;

        my $obj_tag_iter
            = MT::ObjectTag->load_iter( { tag_id => \@bad_ids } );

        while ( my $obj_tag = $obj_tag_iter->() ) {
            $obj_tag->tag_id( $good_tag->id );
            $obj_tag->save;
        }

        # kill the bad tags
        MT::Tag->remove( { id => \@bad_ids } );
    }
}

sub repair_tag_dupes {
    my @dupes = tag_dupes();
    repair_tag_dupe(@$_) foreach @dupes;
}

sub tag_n8d {
    MT::Tag->load( { id => \'= tag_n8d_id' } );
}

sub repair_tag_n8d {
    my @tags = tag_n8d();

    # basic save is enough to fix these
    {
        local $MT::CallbacksEnabled = 0;

        $_->save foreach @tags;
    }
}

sub tag_bad_n8d {
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

sub repair_bad_n8d {
    my @tags = tag_bad_n8d();
    {
        local $MT::CallbacksEnabled = 0;
        $_->[0]->save foreach @tags;
    }
}

sub tag_no_n8d {
    my @no_n8d = ();
    my $iter = MT::Tag->load_iter( { n8d_id => '0' } );
    while ( my $tag = $iter->() ) {
        my $n8d = MT::Tag->normalize( $tag->name );
        push @no_n8d, $tag if $tag->name ne $n8d;
    }

    @no_n8d;
}

sub repair_no_n8d {
    my @tags = tag_no_n8d();
    {
        local $MT::CallbacksEnabled = 0;
        $_->save foreach @tags;
    }
}

1;
