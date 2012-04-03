package Test::MT::TagRepair::Suite::Compile;

=head1 NAME

Test::MT::TagRepair::Suite::Compile

=head1 DESCRIPTION

This class tests that all TagRepair modules compile successfully

=cut

use strict;
use warnings;
use Test::More;

=pod

find $HOME/Dropbox/Code/mt-plugin-tag-repair/lib/TagRepair -name '*.pm' | cut -f8- -d'/' | sed -e "s/\//::/g" -e 's/.pm$//' | pbcopy ; echo OK
OK

=cut
use_ok($_) foreach qw(
    MT::TagRepair
    MT::TagRepair::Report
    MT::TagRepair::Repair
);

done_testing();

1;

__END__


