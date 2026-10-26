package Arith;

use strict;
use warnings;

our $VERSION = '0.01';

use Exporter 'import';
our @EXPORT_OK = qw(add);

sub add {
    my ($x, $y) = @_;
    return $x + $y;
}

1;

__END__

=head1 NAME

Arith - a tiny arithmetic module

=head1 SYNOPSIS

    use Arith qw(add);
    my $sum = add(2, 3);   # 5

=head1 DESCRIPTION

Single-function module used as an integration smoke check for the
burt-agent workspace repository. It is deliberately tiny.

=head1 FUNCTIONS

=head2 add

    my $sum = add($x, $y);

Returns the numeric sum of its two arguments.

=head1 LICENSE

Same terms as Perl itself.

=cut
