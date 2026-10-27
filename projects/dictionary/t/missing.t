use strict;
use warnings;
use Test::More;

use TestUtil;
use Dictionary::Client;
use Dictionary::Error;

sub lookup_with {
    my ($response, $word) = @_;
    $word = 'missing' if @_ < 2;
    my ($fetcher, $seen) = recorded_fetcher($response);
    my $client = Dictionary::Client->new(base_url => 'http://api.invalid/v1', fetcher => $fetcher);
    my $error = eval { $client->lookup($word); 1 } ? undef : $@;
    return ($error, $seen);
}

my ($not_found, $seen) = lookup_with(
    { status => 404, body => '{"title":"No Definitions Found"}', content_type => 'application/json' },
    'florble',
);
isa_ok($not_found, 'Dictionary::Error', '404 raises Dictionary::Error');
is($not_found->kind, 'not_found', '404 maps to not_found');
is($not_found->status, 404, '404 status preserved');
like($not_found->message, qr/florble/, 'message names the missing word');
is_deeply($seen, ['http://api.invalid/v1/entries/en/florble'], 'exactly one request attempted');

my ($empty_array) = lookup_with({ status => 200, body => '[]', content_type => 'application/json' });
is($empty_array->kind, 'not_found', 'empty array maps to not_found');
ok(!defined $empty_array->status, 'unmatched-body not_found has no HTTP status');

my ($null_body) = lookup_with({ status => 200, body => 'null', content_type => 'application/json' });
is($null_body->kind, 'not_found', 'null body maps to not_found');

my ($objects_only) = lookup_with({ status => 200, body => '[null, "x", 3]', content_type => 'application/json' });
is($objects_only->kind, 'not_found', 'array without objects maps to not_found');

my ($empty_body) = lookup_with({ status => 200, body => '', content_type => 'application/json' });
is($empty_body->kind, 'parse', 'empty body is a parse error, not a crash');

my ($blank, $blank_seen) = lookup_with({ status => 200, body => '[]' }, '');
is($blank->kind, 'usage', 'blank word rejected before any request');
is_deeply($blank_seen, [], 'no HTTP request made for a blank word');

my ($slash) = lookup_with({ status => 200, body => '[]' }, 'a/b');
is($slash->kind, 'usage', 'slash in word rejected, so no path injection');

my ($backslash) = lookup_with({ status => 200, body => '[]' }, 'a\\b');
is($backslash->kind, 'usage', 'backslash in word rejected');

my ($control) = lookup_with({ status => 200, body => '[]' }, "ab\x00cd");
is($control->kind, 'usage', 'control characters rejected');

my ($whitespace) = lookup_with({ status => 200, body => '[]' }, '   ');
is($whitespace->kind, 'usage', 'whitespace-only word rejected');

my ($undef_word) = lookup_with({ status => 200, body => '[]' }, undef);
is($undef_word->kind, 'usage', 'undef word rejected');

done_testing;
