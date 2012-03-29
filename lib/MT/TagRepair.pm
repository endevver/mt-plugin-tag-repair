package MT::TagRepair;

=head1 NAME

MT::TagRepair - A repair object for corrupted MT::Tag objects

=cut
use strict;
use warnings;
use Data::Dumper;
use Carp qw( croak cluck confess carp );

use MT::Log::Log4perl qw(l4mtdump); use Log::Log4perl qw( :resurrect );
###l4p our $logger = MT::Log::Log4perl->new();

use MT::Tag;
use MT::ObjectTag;

use base qw( Class::Accessor::Fast );

__PACKAGE__->mk_accessors(qw( verbose dryrun ));


=head1 METHODS

=cut

=head2 CASE_SENSITIVE_LOAD

Constant method which returns the arguments necessary to make MT::Object
loads case-sensitive.  This is purely for convenience because the syntax
is ugly and arcane.

=cut
sub CASE_SENSITIVE_LOAD { binary => { name => 1 } };

=head2 output

A method which intelligently prints the output it is provided. The output is
intelligent because of its variable handling of the input it receives.

Given a B<scalar>, the method acts precisely like the C<print> function:

    $self->output('Hello world');   # Outputs: Hello world

Given an B<array>, the method does the same but joins the array
elements together with an intervening space:

    $self->output(1..10);           # Outputs: 1 2 3 4 5 6 7 8 9 10

Given an B<array reference>, the method feeds the elements of the array to
the C<printf> function:

    my @data = ( name => 'Fred', number => '212-555-1212' );
    $self->output([ 'My %s is %s and my %s is %s', @data ]);
        # Outputs: My name is Fred and my number is 212-555-1212

Unlike the C<report> method, this method outputs data regardless of the value
of the C<verbose> property.

=cut
sub output {
    my $self  = shift;
    my @input = @_;

    if (@input == 1 and 'ARRAY' eq ref($_[0]) ) {
        my $msg = shift @input;
        printf "$msg\n", map { defined($_) ? $_ : 'UNDEF' } @_;
    }
    else {
        print join(' ', @_)."\n";
    }
}

=head2 output_header

This method takes a simple string and outputs it with additional decoration
suitable for use as a section header.  The decoratin format is defined by the
C<_header> method.

=cut
sub output_header {
    my $self = shift;
    $self->output( $self->_header(@_) );

}

=head2 report

This method is identical to the C<output> method except that it respects the
verbose setting.  It's generally used for reporting detailed progress of the
application.

=cut
sub report {
    my $self = shift;
    $self->output(@_) if $self->verbose;
}

=head2 report_header

This method is the verbose-flag-respecting analog to the C<output_header>
method.

=cut
sub report_header {
    my $self = shift;
    $self->report( $self->_header(@_) );
}

=head2 _header

This method defines and returns the format and additional string decoration
surrounding the string provided to the C<report_header> and C<output_header>
methods.

=cut
sub _header {
    my $self = shift;
    return ( "\n\n###### %s ######\n\n", shift() );
}

=head2 load

This load method centralizes all of the load actions undertaken by the class
and, like the C<save> and C<remove> provides consistency and predictability
for the most used functions.

=cut
sub load {
    my $self = shift;
    my ($class, $terms, $args) = @_;
    local $MT::CallbacksEnabled = 0;

    my $init_errstr = $class->errstr;

    # $self->report( 'Loading %s records with terms: %s',
    #                 $class, Dumper($terms) );
    my @obj = $class->load( $terms, $args );

    @obj and return wantarray ? @obj : shift @obj;

    if ( $class->errstr and $class->errstr ne $init_errstr ) {
        $self->throw( load_error => $class, terms => $terms, fatal => 1 );
    }
    return wantarray ? () : undef;
}

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
        my $obj_type = lc($obj->class_label);
        $self->report(
            $obj->id  ?  ( 'Saving %s ID %d', $obj_type, $obj->id )
                      :  ( 'Saving new %s %s',
                            $obj_type,
                            $obj_type eq 'tag' ? "'".$obj->name."'"
                                               : Dumper($obj->column_values) )
        );
        unless ( $self->dryrun ) {
            $obj->save or $self->throw( save_error => $obj );
        }
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
        $self->report( 'Removing %s ID %s', lc( $obj->class_label ), $obj->id);
        unless ( $self->dryrun ) {
            $obj->remove or $self->throw( remove_error => $obj );
        }
    }
}

sub throw {
    my $self = shift;
    my ($type, $obj, %args) = @_;
    my $obj_type = lc($obj->class_label);

    my %exceptions = (
        save_error   => {
            fatal    => 1,
            message  => [

                $obj->id  ?  ( 'Error saving %s (ID:%d): %s',
                               $obj_type, $obj->id, $self->errstr($obj) )
                          :  ( "Error saving new %s: %s\n%s",
                                $obj_type, $self->errstr($obj), Dumper($obj) ),
            ],
        },
        remove_error => {
            fatal    => 1,
            message  => [ 'Error removing %s (ID:%d): %s',
                            $obj_type, $obj->id, $self->errstr($obj) ],
        },
        load_error   => {
            fatal    => $args{fatal},
            message  => [ 'Error loading %s records: %s. Load terms: %s',
                          $obj, $self->errstr($obj), Dumper($args{terms}) ],
        },
    );

    my $exception = $exceptions{$type}
        or croak "Undefined exception type thrown: $type";
    my ( $msg, @msg_args ) = @{ $exception->{message} };

    $msg = sprintf( $msg, @msg_args );

    $exception->{fatal} ? croak $msg : carp $msg;
}

sub errstr {
    my $self = shift;
    return shift()->errstr || 'UNKNOWN ERROR';
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
            sort   => [
                { column => 'count(*)', desc => 'DESC' },
                { column => 'name' }
            ],
            CASE_SENSITIVE_LOAD(),
        }
    );

    my @tag_groups = ();
    my %duped      = ();
    while ( my ( $count, $name ) = $iter->() ) {
        next unless $count > 1;         # Skip groups with only 1 tag (good!) 

        # Load and iterate through all tags with current $name (case-insensitive)
        my @tags = $self->load( 'MT::Tag', { name => $name } );
        foreach my $tag ( @tags ) {

            next if $duped{ $tag->name }++;    # Don't reprocess the dupes

            # Get the count of tags which match this tag's name in a
            # CASE-SENSITIVE fashion since case variants are not considered
            # duplicates
            my $identical = MT::Tag->count( { name => $tag->name },
                                            { CASE_SENSITIVE_LOAD() } );

            if ( $identical > 1 ) {
                push @tag_groups, [
                    $self->load( 'MT::Tag', { name => $tag->name    },
                                            { CASE_SENSITIVE_LOAD() }, )
                ];
            }
        }
    }
    @tag_groups;
}

=head2 tag_self_n8d

Find all tags where id and n8d_id are equal.  This should never happen.

=cut
sub tag_self_n8d {
    my $self = shift;
    $self->load( 'MT::Tag', { id => \'= tag_n8d_id' } );
}

=head2 tag_bad_n8d

Find all tags which declare a non-existent or completely unrelated tag as its
normalized version (n8d_id) (i.e. not 0 and n8_id != id).  This method returns
and array of array references containing the tag and its incorrect referent
or undef if the n8d_id points to a non-existent tag.

=cut
sub tag_bad_n8d {
    my $self = shift;
    my @bad_n8d = ();
    my $iter = MT::Tag->load_iter( { n8d_id => { not => '0' } } );
    while ( my $tag = $iter->() ) {

        # Self-normalized tags are dealt with in tag_self_n8d()
        next if $tag->n8d_id and $tag->id == $tag->n8d_id;

        my $n8d_tag = MT::Tag->lookup( $tag->n8d_id );
        push @bad_n8d, [ $tag, $n8d_tag ]
            if ! $n8d_tag
            or $tag->normalize ne $n8d_tag->name;
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
        push @no_n8d, $tag
            unless $tag->name eq $tag->normalize;
    }

    @no_n8d;
}

##################### REPAIR METHODS ######################

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
