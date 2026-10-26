use strict;
use warnings;
use Test::More;

use lib 'lib';
use Arith qw(add);

ok defined &add, 'add() was exported';

# --- positive inputs ---
is add(1, 2), 3, 'add(1, 2) == 3';
is add(10, 32), 42, 'add(10, 32) == 42';
is add(0.5, 0.25), 0.75, 'add(0.5, 0.25) == 0.75';

# --- zero inputs ---
is add(0, 0), 0, 'add(0, 0) == 0';
is add(0, 7), 7, 'add(0, 7) == 7';
is add(7, 0), 7, 'add(7, 0) == 7';

# --- negative inputs ---
is add(-3, -4), -7, 'add(-3, -4) == -7';
is add(-5, 3), -2, 'add(-5, 3) == -2';
is add(5, -9), -4, 'add(5, -9) == -4';
is add(-1, 1), 0, 'add(-1, 1) == 0';

# --- identity / symmetry sanity ---
is add(123456, 654321), 777777, 'add(123456, 654321) == 777777';
is add(-2.5, -0.5), -3, 'add(-2.5, -0.5) == -3';
is add(-0.1, 0.1), 0, 'add(-0.1, 0.1) == 0';

# commutativity over a small grid of values
my @vals = (-5, -1, 0, 1, 5);
my $commutative = 1;
for my $a (@vals) {
    for my $b (@vals) {
        $commutative = 0 if add($a, $b) != add($b, $a);
    }
}
ok $commutative, 'add() is commutative over {-5,-1,0,1,5}';

done_testing;
