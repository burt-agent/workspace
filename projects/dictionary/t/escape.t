use strict;
use warnings;
use Test::More;

use Dictionary::Client;

my $class = 'Dictionary::Client';

# Plain byte-string words must escape, not vanish. Regression: the UTF-8 probe
# used to consume the caller's scalar and return an empty string.
is($class->uri_escape('plain'), 'plain', 'unreserved characters are left alone');
is(Dictionary::Client::uri_escape('plain'), 'plain', 'plain-function call style works too');
is($class->uri_escape('a b/c'), 'a%20b%2Fc', 'space and slash are escaped');
is($class->uri_escape('a~b_c-d.e'), 'a~b_c-d.e', 'unreserved marks survive');

# Encoding: characters, UTF-8 bytes, and Latin-1 bytes all land on one encoding.
is($class->uri_escape("caf\x{e9}"), 'caf%C3%A9', 'character string encoded as UTF-8');
is($class->uri_escape("na\x{ef}ve"), 'na%C3%AFve', 'non-ASCII characters escaped octet by octet');
is($class->uri_escape('caf' . chr(0xc3) . chr(0xa9)), 'caf%C3%A9', 'UTF-8 bytes are not double-encoded');
is($class->uri_escape('caf' . chr(0xe9)), 'caf%C3%A9', 'Latin-1 bytes lifted to UTF-8 once');

# Degenerate input.
is($class->uri_escape(''), '', 'empty word encodes to empty string');
is($class->uri_escape(undef), '', 'undef word encodes to empty string');

# Escaping must not disturb the caller's own scalar.
my $word = 'cafe';
is($class->uri_escape($word), 'cafe', 'unflagged word escapes');
is($word, 'cafe', 'the caller word is left untouched');

my $bytes = 'caf' . chr(0xc3) . chr(0xa9);
is($class->uri_escape($bytes), 'caf%C3%A9', 'unflagged UTF-8 word escapes');
is($bytes, 'caf' . chr(0xc3) . chr(0xa9), 'unflagged UTF-8 word is left untouched');

done_testing;
