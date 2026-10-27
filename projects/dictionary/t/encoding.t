use strict;
use warnings;
use Test::More;

use Encode ();
use TestUtil;
use Dictionary::Client;
use Dictionary::Error;

sub entry_from {
    my ($body, $content_type) = @_;
    $content_type = 'application/json' unless defined $content_type;
    my ($fetcher, $seen) = recorded_fetcher({ status => 200, body => $body, content_type => $content_type });
    my $client = Dictionary::Client->new(base_url => 'http://api.invalid/v1', fetcher => $fetcher);
    return ($client->lookup("caf\x{e9}"), $seen);
}

my $raw_bytes = '[{"word":"caf' . "\xc3\xa9" . '","phonetic":"kaf","meanings":[]}]';
my $escaped  = '[{"word":"caf\\u00e9","phonetic":"kaf","meanings":[]}]';

my ($from_bytes) = entry_from($raw_bytes, 'application/json; charset=utf-8');
my ($from_escapes) = entry_from($escaped, 'application/json');

is($from_bytes->{word}, $from_escapes->{word}, 'raw UTF-8 bytes and \\u escapes decode identically');
is($from_bytes->{word}, "caf\x{e9}", 'decoded to the expected characters');
ok(utf8::is_utf8($from_bytes->{word}), 'word is a character string, not raw bytes');
is(length($from_bytes->{word}), 4, 'four characters, not five bytes');
is(Encode::encode('UTF-8', $from_bytes->{word}), "caf\xc3\xa9", 're-encodes to the original two bytes');

# Double-encoding guard: \u00c3\u00a9 is mojibake, not the same string.
my ($mojibake) = entry_from('[{"word":"caf\\u00c3\\u00a9"}]');
isnt($mojibake->{word}, $from_bytes->{word}, 'mojibake is not silently treated as the right word');
is(length($mojibake->{word}), 5, 'mojibake keeps both characters');

# charset from the header is honoured, including non-UTF-8.
my ($latin1) = entry_from('[{"word":"caf' . "\xe9" . '"}]', 'application/json; charset=iso-8859-1');
is($latin1->{word}, "caf\x{e9}", 'iso-8859-1 body decoded via Encode, not assumed UTF-8');

my ($upper) = entry_from('[{"word":"caf' . "\xc3\xa9" . '"}]', 'Application/JSON; Charset=UTF-8');
is($upper->{word}, "caf\x{e9}", 'charset parameter parsed case-insensitively');

my ($defaulted) = entry_from('[{"word":"caf' . "\xc3\xa9" . '"}]', 'application/json');
is($defaulted->{word}, "caf\x{e9}", 'missing charset defaults to UTF-8');

my ($bom) = entry_from("\xef\xbb\xbf[{\"word\":\"caf" . "\xc3\xa9" . "\"}]", 'application/json; charset=utf-8');
is($bom->{word}, "caf\x{e9}", 'a UTF-8 BOM does not corrupt the payload');

# The query word is percent-encoded from characters, so it survives the round trip.
my ($client, $seen) = entry_from('[{"word":"caf' . "\xc3\xa9" . '"}]', 'application/json');
is($seen->[0], 'http://api.invalid/v1/entries/en/caf%C3%A9', 'request path is UTF-8 percent-encoded once');

my $escaped_once = Dictionary::Client->uri_escape("caf\x{e9}");
isnt($escaped_once, 'caf%25C3%25A9', 'percent-escaping is not applied twice');

done_testing;
