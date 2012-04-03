package Test::MT::TagRepair::Base;

use Test::MT::Base;
use parent qw( Test::MT::Base );

sub set_tagdata_to {
    my $self = shift;
    my $data = shift;
    MT::Tag->remove_all;
}
1;