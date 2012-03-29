package MT::TagRepair::Report;

use strict;
use warnings;

use base qw( MT::TagRepair );

use MT::Log::Log4perl qw(l4mtdump); use Log::Log4perl qw( :resurrect );
###l4p our $logger = MT::Log::Log4perl->new();
# ###l4p $logger ||= MT::Log::Log4perl->new(); $logger->trace();

sub class_label { 'Report' }

sub execute {
    my $self = shift;
    $self->report_header( 'Starting Tag and ObjectTag analysis' );
    $self->SUPER::execute();
}

sub report_tag_dupes {
    my $self = shift;

    $self->report_header('Duplicate tags (case-sensitive)');

    my @tag_dupes = $self->tag_dupes;

    my $dupe_count = 0;
    $dupe_count += scalar @$_ - 1 foreach @tag_dupes;

    if ( $self->verbose ) {
        $self->report( '%-6s %s', "Tags", 'Duplicated tag names');
        $self->report( '%-6d %s', scalar @$_, $_->[0]->name )
            foreach @tag_dupes;
    }
    printf "%d duplicate tags (%d duped names).\n",
        $dupe_count, scalar @tag_dupes;
}

sub report_self_n8d {
    my $self = shift;

    $self->report_header(
        'Circular (i.e. self-referential) normalization'
    );
    my @self_n8d = $self->tag_self_n8d;

    if ( $self->verbose ) {
        print "\n\n";
        foreach my $tag (@self_n8d) {
            print $tag->name
                . " considers itself to be its normalized version.\n";
        }
    }

    print scalar @self_n8d
        . " tag(s) which have a circular, self-referential normalized tag reference.\n";
}

sub report_bad_n8d {
    my $self = shift;
    
    $self->report_header(
        'Incorrect/non-existent normalization references'
    );
    my @bad_n8d = $self->tag_bad_n8d;

    if ( $self->verbose ) {
        print "\n\n";
        foreach my $tags (@bad_n8d) {
            print "'" . $tags->[0]->name . "' considers ";
            if ( $tags->[1] ) {
                print "'" . $tags->[1]->name . "'";
            }
            else {
                print "a non-existant tag";
            }
            print " to be its normalized version.\n";
        }
    }

    print scalar @bad_n8d
        . " tags(s) which reference a non-existent or incorrect normalized tag.\n";
}

sub report_no_n8d {
    my $self = shift;
    
    $self->report_header(
        'False declaration of normalization'
    );
    my @no_n8d = $self->tag_no_n8d;

    if ( $self->verbose ) {
        print "\n\n";

        foreach my $tag (@no_n8d) {
            print "'"
                . $tag->name
                . "' is not normalized and has no reference to a normalized tag.\n";
        }
    }

    print scalar @no_n8d
        . " false normalized form declarations by non-normalized tag(s).\n";
}


1;