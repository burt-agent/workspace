use strict;
use warnings;
use Test::More;

use lib 'lib';
use Arith qw(add subtract);

ok defined &add, 'add() was exported';
ok defined &subtract, 'subtract() was exported';

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

# --- subtract: basic positive inputs ---
is subtract(5, 3), 2, 'subtract(5, 3) == 2';
is subtract(3, 5), -2, 'subtract(3, 5) == -2';
is subtract(42, 42), 0, 'subtract(42, 42) == 0';

# --- subtract: zero inputs ---
is subtract(0, 0), 0, 'subtract(0, 0) == 0';
is subtract(0, 7), -7, 'subtract(0, 7) == -7';
is subtract(7, 0), 7, 'subtract(7, 0) == 7';

# --- subtract: negative inputs ---
is subtract(-3, -4), 1, 'subtract(-3, -4) == 1';
is subtract(-5, 3), -8, 'subtract(-5, 3) == -8';
is subtract(5, -9), 14, 'subtract(5, -9) == 14';
is subtract(-1, 1), -2, 'subtract(-1, 1) == -2';

# --- subtract: floats ---
is subtract(0.75, 0.25), 0.5, 'subtract(0.75, 0.25) == 0.5';
is subtract(-2.5, -0.5), -2, 'subtract(-2.5, -0.5) == -2';
is subtract(-0.1, 0.1), -0.2, 'subtract(-0.1, 0.1) == -0.2';

# --- subtract: inverse relationship with add ---
is subtract(add(6, 4), 4), 6, 'subtract(add(6, 4), 4) == 6';
is add(subtract(6, 4), 4), 6, 'add(subtract(6, 4), 4) == 6';

# --- subtract: big values and identity ---
is subtract(777777, 654321), 123456, 'subtract(777777, 654321) == 123456';
is subtract(123456, 123456), 0, 'subtract(123456, 123456) == 0 (a - a == 0)';

# subtract is anti-commutative over a small grid of values
my $anti_commutative = 1;
for my $a (@vals) {
    for my $b (@vals) {
        $anti_commutative = 0 if subtract($a, $b) != -subtract($b, $a);
    }
}
ok $anti_commutative, 'subtract() is anti-commutative over {-5,-1,0,1,5}';

# add and subtract are consistent on the same operands
my $consistent = 1;
for my $a (@vals) {
    for my $b (@vals) {
        $consistent = 0 if add($a, $b) != subtract($a, -$b);
    }
}
ok $consistent, 'add($a, $b) == subtract($a, -$b) over {-5,-1,0,1,5}';

done_testing;
