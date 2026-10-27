use strict;
use warnings;
use Test::More;

use TestUtil;
use Dictionary::Client;
use Dictionary::Error;

my $body = fixture_bytes('neighbors.json');

sub client_with {
    my (%arg) = @_;
    my ($fetcher, $seen) = recorded_fetcher($arg{response});
    my $client = Dictionary::Client->new(
        base_url => 'http://api.invalid/v1',
        fetcher  => $fetcher,
        (exists $arg{max_neighbors} ? (max_neighbors => $arg{max_neighbors}) : ()),
    );
    return ($client, $seen);
}

my ($client, $seen) = client_with(
    response => { status => 200, body => $body, content_type => 'application/json' },
    max_neighbors => 10,
);
my $words = $client->neighbors("caf\x{e9}");

is_deeply($seen, ['http://api.invalid/v1/neighbors/en/caf%C3%A9'], 'requested the escaped neighbors URL');
is_deeply($words, ['coffee', 'diner', 'espresso', 'bistro', 'bar'], 'strings and objects merged, deduped, self removed');

my ($capped) = client_with(
    response => { status => 200, body => $body, content_type => 'application/json' },
    max_neighbors => 3,
);
is_deeply($capped->neighbors("caf\x{e9}"), ['coffee', 'diner', 'espresso'], 'max_neighbors caps the list');

my ($zero) = client_with(
    response => { status => 200, body => $body, content_type => 'application/json' },
    max_neighbors => 0,
);
is_deeply($zero->neighbors("caf\x{e9}"), [], 'max_neighbors of 0 yields an empty list');

my ($unlimited) = client_with(
    response => { status => 200, body => $body, content_type => 'application/json' },
    max_neighbors => undef,
);
is(scalar @{ $unlimited->neighbors("caf\x{e9}") }, 5, 'undef max_neighbors disables the cap');

my ($empty) = client_with(response => { status => 200, body => '[]', content_type => 'application/json' });
is_deeply($empty->neighbors('anything'), [], 'empty array yields an empty list');

my ($notarray) = client_with(response => { status => 200, body => '{"word":"x"}', content_type => 'application/json' });
is_deeply($notarray->neighbors('x'), [], 'non-array body yields an empty list');

my ($junk) = client_with(response => { status => 200, body => '[null, 5, {"word":""}, {"nope":1}, "bar"]', content_type => 'application/json' });
is_deeply($junk->neighbors('x'), ['bar'], 'unusable neighbor entries skipped');

# Neighbors that only differ by case are collapsed after the first occurrence.
my ($case) = client_with(response => { status => 200, body => '["Tea","tea","TEA"]', content_type => 'application/json' });
is_deeply($case->neighbors('x'), ['Tea'], 'case-insensitive dedupe keeps the first spelling');

done_testing;
