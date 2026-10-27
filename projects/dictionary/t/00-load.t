use strict;
use warnings;
use Test::More;

use_ok('Dictionary::Error');
use_ok('Dictionary::Client');

can_ok('Dictionary::Client', qw(new lookup lookup_all neighbors normalize_entry uri_escape));

my $error = Dictionary::Error->new(kind => 'parse', status => 500, message => 'boom');
isa_ok($error, 'Dictionary::Error');
is($error->kind, 'parse', 'kind accessor');
is($error->status, 500, 'status accessor');
like("$error", qr/parse.*500.*boom/, 'stringifies with kind, status and message');

my $plain = Dictionary::Error->new(kind => 'usage', message => 'nothing');
is("$plain", 'usage: nothing', 'stringifies without a status');

my $client = Dictionary::Client->new(base_url => 'http://example.invalid/v1/');
is($client->base_url, 'http://example.invalid/v1', 'trailing slash trimmed');
is($client->lang, 'en', 'default language');

my $french = Dictionary::Client->new(base_url => 'http://example.invalid/v1', lang => 'fr', max_neighbors => 3);
is($french->lang, 'fr', 'explicit language');

is(Dictionary::Client->uri_escape('plain'), 'plain', 'unreserved word untouched');
is(Dictionary::Client->uri_escape("caf\x{e9}"), 'caf%C3%A9', 'UTF-8 percent encoding');
is(Dictionary::Client->uri_escape("caf" . chr(0xc3) . chr(0xa9)), 'caf%C3%A9', 'byte string encoded as-is');

is_deeply(Dictionary::Client->uri_escape('a b/c'), 'a%20b%2Fc', 'space and slash escaped');

done_testing;
