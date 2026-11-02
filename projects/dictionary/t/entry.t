use strict;
use warnings;
use Test::More;
use Encode ();

use lib '../lib';
use TestUtil;
use Dictionary::Client;
use Dictionary::Error;

my $body = fixture_bytes('entry_cafe.json');
my $client_for = sub {
    my ($response) = @_;
    my ($fetcher, $seen) = recorded_fetcher($response);
    return (Dictionary::Client->new(base_url => 'http://api.invalid/v1', fetcher => $fetcher), $seen);
};

my ($client, $seen) = $client_for->({ status => 200, body => $body, content_type => 'application/json; charset=utf-8' });
my $entry = $client->lookup("caf\x{e9}");

is_deeply($seen, ['http://api.invalid/v1/entries/en/caf%C3%A9'], 'requested the escaped entry URL once');
is($entry->{word}, "caf\x{e9}", 'word decoded from \\u escape');
is($entry->{phonetic}, "k\x{259}\x{2c8}fe\x{26a}", 'phonetic survives multi-byte escapes');
is($entry->{origin}, 'French', 'origin carried through');
is($entry->{audio}, 'http://audio.invalid/cafe.mp3', 'first non-empty audio picked');

is(scalar @{ $entry->{meanings} }, 2, 'both meanings kept');
is($entry->{meanings}[0]{part_of_speech}, 'noun', 'part of speech mapped');
is(scalar @{ $entry->{meanings}[0]{definitions} }, 2, 'both definitions kept');
is($entry->{meanings}[0]{definitions}[0]{definition}, 'A coffee shop.', 'definition text');
is($entry->{meanings}[0]{definitions}[0]{example}, "meet me at the caf\x{e9}", 'example text decoded');
is_deeply($entry->{meanings}[0]{definitions}[0]{synonyms}, ['coffee shop'], 'definition synonyms');
is_deeply($entry->{meanings}[0]{definitions}[0]{antonyms}, [], 'missing antonyms default to empty list');
is($entry->{meanings}[0]{definitions}[1]{example}, '', 'missing example defaults to empty string');
is($entry->{meanings}[1]{part_of_speech}, 'verb', 'second meaning kept');

is_deeply($entry->{meanings}[1]{synonyms}, [], 'meaning-level synonyms default to empty list');

# lookup_all keeps every entry in the array.
my ($multi, $multi_seen) = $client_for->({ status => 200, body => $body, content_type => 'application/json' });
my $all = $multi->lookup_all("caf\x{e9}");
is(scalar @$all, 2, 'lookup_all returns both entries');
is($all->[1]{word}, "caf\x{e9}", 'second entry word');
is_deeply($all->[1]{meanings}, [], 'entry without meanings normalizes to empty list');
is($all->[1]{phonetic}, '', 'absent phonetic normalizes to empty string');

# A bare object (not wrapped in an array) is accepted.
my ($single, $single_seen) = $client_for->({ status => 200, body => '{"word":"solo"}', content_type => 'application/json' });
my $solo = $single->lookup('solo');
is($solo->{word}, 'solo', 'single-object response accepted');

# normalize_entry is defensive about junk.
my $junk = Dictionary::Client->normalize_entry({ meanings => 'nope', phonetics => [ {}, 'x' ], word => undef });
is($junk->{word}, '', 'undef word becomes empty string');
is_deeply($junk->{meanings}, [], 'non-array meanings becomes empty list');
is($junk->{audio}, '', 'no usable audio');

my $noarg = eval { Dictionary::Client->normalize_entry(undef) };
isa_ok($noarg, 'HASH', 'normalize_entry tolerates undef input');

done_testing;
