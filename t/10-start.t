package Test::MT::TagRepair::Suite::Start;

=head1 NAME

Test::MT::TagRepair::Suite::Start

=head1 DESCRIPTION

This class tests the methods and functionality of the
L<TagRepair::Plugin> class.

=cut

use Test::MT;
use Test::MT::Base;
use parent qw( Test::MT::TagRepair::Base );
my $test     = __PACKAGE__->construct_default();
# my $env      = $test->env;
# my $data     = $test->env->data;
# my $env_data = $test->env->data->env_data;

my $app  = $test->app;

my ($Entry, $Tag, $OTag )
    = map { $app->model($_) } qw( entry tag objecttag );

subtest "Setup" => 
    sub {
        is( $Entry, 'MT::Entry',     'Entry class'     );
        is( $Tag,   'MT::Tag',       'Tag class'       );
        is( $OTag,  'MT::ObjectTag', 'ObjectTag class' );

        cmp_ok( $Entry->count(), '>', 0, 'Have entries'    );
        cmp_ok(   $Tag->count(), '>', 0, 'Have tags'       );
        cmp_ok(  $OTag->count(), '>', 0, 'Have objecttags' );

        $_->remove_all() foreach $Tag, $OTag;
        is( $Tag->count(),  0, 'Tags reset'       );
        is( $OTag->count(), 0, 'ObjectTags reset' );
    };

my %columns = (
    $Tag  => [qw(  id  name       n8d_id  is_private  )],
    $OTag => [qw(  id  object_id  tag_id  blog_id     object_datasource  )],
);

my %starting = (
        #            id    name            n8d_id       is_private
    $Tag  => 
            [
                [qw(  1    Developers      1            0          )],
                [qw(  2    DEVELOPERS      1            0          )],
                [qw(  3    developers      0            0          )],
                [qw(  4    DeVeLoPeRs      1            0          )],
                [qw(  5    developers      0            0          )],
            ],
        #            id    name            n8d_id       is_private
    $OTag =>
            [
                [qw(  1    Developers      1            0          )],
                [qw(  2    DEVELOPERS      1            0          )],
                [qw(  3    developers      0            0          )],
                [qw(  4    DeVeLoPeRs      1            0          )],
                [qw(  5    developers      0            0          )],
            ],
);

subtest "Record loading" =>
    sub {
        foreach my $class ( $Tag, $OTag ) {
            my $records = load_records(
                $class,
                $columns{$class},
                $starting{$class},
            );
            cmp_ok( @$records, '==', @{$starting{$class}}, "$class record count" );
            diag explain $_->column_values foreach @$records;
            # my $otag_records = load_records( @otags );
            # is( scalar @$otag_records, 3, 'OTag count' );
            # diag explain $_->column_values foreach @$otag_records;
        }
    };

subtest "Tag repair process" =>
    sub {
        require MT::TagRepair::Repair;
        my $process =  new_ok('MT::TagRepair::Repair', [
            issues  => [qw( tag_dupes self_n8d bad_n8d no_n8d )],
            verbose => 1,
            dryrun  => 0,
        ]);
        # my $process = MT::TagRepair::Repair->new({
        # });

        is( $process->execute(), 1, 'Tag repair execution' );

    };

my %expected = (
    $Tag => {
            # ID          Name        N8d  Pri
              3  => [qw(  developers  0    0  )],
              4  => [qw(  DeVeLoPeRs  3    0  )],
              #5 => [qw(  developers  0    0  )],
              6  => [qw(  Developers  3    0  )],
              7  => [qw(  DEVELOPERS  3    0  )],
    },
    $OTag => {
            #  ID           Obj ID   Tag ID   blog_id   obj_ds
               #1 => [qw(   1        1        1         entry  )],
               #2 => [qw(   2        2        1         entry  )],
                3 => [qw(   3        3        1         entry  )],
                4 => [qw(   3        4        1         entry  )],
               #5 => [qw(   1        5        1         entry  )],
                6 => [qw(   1        6        1         entry  )],
                7 => [qw(   2        7        1         entry  )],
    },
);

subtest "Final result verification" => 
foreach my $obj ( $Tag->load(), $OTag->load() ) {
    my $class = ref $obj;
    my $expect = $expected{$class}->{$obj->id};
    my @vals = map { $obj->$_ } 
               grep { ! /^id$/ } @{ $columns{$class} };
    is_deeply( \@vals, $expect, "$class ID ".$obj->id." values" );
}

pass('WHEEEEEEE');

# diag explain \%INC;
done_testing();

1;

sub load_records {
    my ( $class, $columns, $data ) = @_;
    my $save_method = MT::Object->can('save');
    my @records;
    require List::MoreUtils;
    foreach my $row ( @$data ) {
        my $record = $class->new();
        $record->set_values({ 
            List::MoreUtils::mesh( @$columns, @$row )
        });
        $record->$save_method()
        # $record->save
            or die sprintf "Error saving %s ID %s: %s",
                $class, $record->id, $record->errstr;
        push( @records, $record );
    }
    \@records;
}

# 
# perldoc -l List::MoreUtils
# mate /Users/jay/perl5/perlbrew/perls/perl-5.10.1/lib/site_perl/5.10.1/darwin-2level/List/MoreUtils.pm
