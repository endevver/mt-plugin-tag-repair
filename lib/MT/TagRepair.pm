package MT::TagRepair;

=head1 NAME

MT::TagRepair - A repair object for corrupted MT::Tag objects

=cut
use strict;
use warnings;
use Data::Dumper;
use Carp qw( croak cluck confess carp );
use Text::Indent;

use MT::Log::Log4perl qw(l4mtdump); use Log::Log4perl qw( :resurrect );
###l4p our $logger = MT::Log::Log4perl->new();
# ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

use MT::Tag;
use MT::ObjectTag;

use base qw( Class::Accessor::Fast );
__PACKAGE__->mk_accessors(qw( verbose dryrun issues ));

use constant INDENT => ' 'x4;

=head1 METHODS

=cut

=head2 start_phase

This method is called at the beginning of all of the major methods which
control the core operation of the plugin and is responsible (when the
utility is run in verbose mode) for outputting a banner header, title and
descriptive text about the process to be undertaken.

If the C<--verbose> flag is not supplied, this method is a no-op.

=cut
sub start_phase {
    my $self    = shift;
    my $header  = $self->_header( +shift );
    my $subtext = shift;
    $self->reset_indent();
    $self->report( $header );
    $self->report( $subtext."\n" ) if $subtext;
    $self->indent();
}

=head2 end_phase

This method is called at the end of all major mode methods. Like
C<start_phase>, it is responsible for outputtng descriptive text, although in
this case, it's a summary of completed actions.

I<Unlike> C<start_phase>, this method's output is I<not governed> by the
C<--verbose> flag.

=cut
sub end_phase {
    my $self    = shift;
    $self->output( @_ ) if @_;
    $self->output("\n") if $self->verbose;
    $self->reset_indent;
}

=head2 execute

This method is the primary dispatcher for the program calling
each requested method in priority order.

=cut
sub execute {
    my $self = shift;

    # Create a mapping of requested actions
    my %requested = map { $_ => 1 } @{ $self->issues };

    # Iterate over the issues in priority order
    foreach my $issue ( $self->issue_priority ) {

        # Skip any mode that was not requested
        next unless $requested{$issue};

        my $method_name = join('_', lc( $self->class_label ), $issue );

        $self->$method_name();
    }
}

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
    my $i     = $self->indenter;

    if ( scalar @input == 1 and 'ARRAY' eq ref($input[0]) ) {

        my $input = shift @input;
        print $i->indent( sprintf( shift @$input, @$input ) );
    }
    else {
        confess( 'Not defined $_[0]' ) unless defined($_[0]);
        @_ and print $i->indent( join(' ', @_) );
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
    my $self    = shift;
    my $header  = $self->_header( +shift );
    my $subtext = shift;
    $self->report( $header );
    $self->report( $subtext ) if $subtext;
}

=head2 _header

This method defines and returns the format and additional string decoration
surrounding the string provided to the C<report_header> and C<output_header>
methods.

=cut
sub _header {
    my $self = shift;
    return [ "###### %s ######\n", @_ ];
}

sub indenter  {
    my $self = shift;
    unless ( $self->{indent} ) {
        my $i = $self->{indent} = Text::Indent->new;
        $i->spaces( length(INDENT) );
        $i->spacechar(' ');
        $i->add_newline(1);
        $i->level(0);
    }
    $self->{indent};
}
sub indent       { $_[0]->indenter->increase( $_[1] ) }
sub outdent      { $_[0]->indenter->decrease( $_[1] ) }
sub reset_indent { $_[0]->indenter->reset()           }

=head2 load

This load method centralizes all of the actions undertaken by the class
in the course of executing search queries. Like the C<save> and C<remove>
this mainly ensures consistency and predictability for the most used functions.

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

sub dump1l {
    my $self = shift;
    local $Data::Dumper::Terse = 1;
    my $out = Dumper( @_ == 1 ? @_ : \@_ );
    $out =~ s{\s*\n+\s*}{}g;
    $out;
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

=head2 tag_desc

=cut
sub tag_desc {
    my $self = shift;
    my $tag  = shift;
    return $tag->id ? sprintf( 'tag "%s" (ID:%d)', $tag->name, $tag->id )
                    : sprintf( 'new tag "%s"',     $tag->name           );
}

=head2 CASE_SENSITIVE_LOAD

This constant method returns the arguments required to make database
searches (MT'::Object's `load` and `load_iter`) B<case-insensitive>.

=cut
sub CASE_SENSITIVE_LOAD { binary => { name => 1 } };

sub debug {}


###################### TAG SEARCH METHODS ######################
###################### TAG SEARCH METHODS ######################
###################### TAG SEARCH METHODS ######################

=head2 issue_priority

This method returns the keywords representing each of the issues the repair
and report classes deal with, in the order that they need to be processed.

=cut
sub issue_priority { qw( tag_dupes bad_n8d no_n8d self_n8d ) }

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

1;
