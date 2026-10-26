package Arith;

use strict;
use warnings;

our $VERSION = '0.02';

use Exporter 'import';
our @EXPORT_OK = qw(add subtract);

sub add {
    my ($x, $y) = @_;
    return $x + $y;
}

sub subtract {
    my ($x, $y) = @_;
    return $x - $y;
}

1;

__END__

=head1 NAME

Arith - a tiny arithmetic module

=head1 SYNOPSIS

    use Arith qw(add subtract);
    my $sum  = add(2, 3);        # 5
    my $diff = subtract(2, 3);   # -1

=head1 DESCRIPTION

Two-function module used as an integration smoke check for the
burt-agent workspace repository. It is deliberately tiny.

=head1 FUNCTIONS

=head2 add

    my $sum = add($x, $y);

Returns the numeric sum of its two arguments.

=head2 subtract

    my $diff = subtract($x, $y);

Returns the numeric difference of its two arguments, C<$x - $y>.
The operation is not commutative: C<subtract($x, $y)> is the negation of
C<subtract($y, $x)>.

=head1 LICENSE

Same terms as Perl itself.

=cut
