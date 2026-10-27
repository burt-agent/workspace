use strict;
use warnings;
use Test::More;
use Encode ();

use TestUtil;
use Dictionary::Client;
use Dictionary::Error;

my $class = 'Dictionary::Client';

sub client_with {
    my ($response) = @_;
    my ($fetcher, $seen) = recorded_fetcher($response);
    my $client = Dictionary::Client->new(base_url => 'http://api.invalid/v1', fetcher => $fetcher);
    return ($client, $seen);
}

sub entry_for {
    my ($body, $word, $content_type) = @_;
    $content_type = 'application/json; charset=utf-8' unless defined $content_type;
    my ($client) = client_with({ status => 200, body => $body, content_type => $content_type });
    my ($entry, $error);
    if (eval { $entry = $client->lookup($word); 1 }) { $error = undef }
    else { $error = $@ }
    return ($entry, $error);
}

sub error_for {
    my ($body, $word, $content_type) = @_;
    my ($entry, $error) = entry_for($body, $word, $content_type);
    return $error;
}

# Decode an already percent-encoded byte string back to raw octets.
sub pct_bytes {
    my ($escaped) = @_;
    my $bytes = '';
    my $index = 0;
    while ($index < length $escaped) {
        my $char = substr($escaped, $index, 1);
        if ($char eq '%') {
            $bytes .= chr hex substr($escaped, $index + 1, 2);
            $index += 3;
        }
        else {
            $bytes .= $char;
            $index += 1;
        }
    }
    return $bytes;
}

# ------------------------------------------------------- reserved characters

# RFC 3986 gen-delims and sub-delims, plus '%'. Leaving any of these raw could
# change how the URL is parsed or truncate the path at a fragment.
my $reserved = q{!*'();:@&=+$,/?#[]%};
is(
    $class->uri_escape($reserved),
    '%21%2A%27%28%29%3B%3A%40%26%3D%2B%24%2C%2F%3F%23%5B%5D%25',
    'every reserved character is percent-encoded with uppercase hex',
);

is($class->uri_escape('a?b#c'), 'a%3Fb%23c', 'query and fragment marks cannot leak into the URL');
is($class->uri_escape('a&b=c'), 'a%26b%3Dc', 'sub-delims are escaped, so no parameter injection');
is($class->uri_escape('a+b'), 'a%2Bb', 'plus is escaped instead of being read as a space');
is($class->uri_escape('100%'), '100%25', 'a literal percent sign is escaped, never passed raw');
is($class->uri_escape('caf%C3%A9'), 'caf%25C3%25A9', 'a pre-escaped word is escaped again, not decoded');
is($class->uri_escape('a b'), 'a%20b', 'space becomes %20, not a plus');
is($class->uri_escape("tab\x{7f}"), 'tab%7F', 'DEL is escaped rather than left unencoded');
is($class->uri_escape("a\x00b"), 'a%00b', 'uri_escape escapes NUL itself when called directly');
is($class->uri_escape('-._~'), '-._~', 'the unreserved marks stay literal');
is($class->uri_escape('AZaz09'), 'AZaz09', 'alphanumerics stay literal');

# ------------------------------------------------------------- unicode escapes

my @cases = (
    ["caf\x{e9}",                  'caf%C3%A9',                  'Latin-1 accent, two bytes'],
    ["na\x{ef}ve",                'na%C3%AFve',                 'diaeresis'],
    ["\x{65e5}\x{672c}\x{8a9e}",  '%E6%97%A5%E6%9C%AC%E8%AA%9E', 'CJK, three bytes each'],
    ["\x{41d}\x{43e}\x{432}",    '%D0%9D%D0%BE%D0%B2',        'Cyrillic, mixed two-byte leads'],
    ["e\x{301}",                  'e%CC%81',                   'combining acute mark after an ASCII letter'],
    ["\x{1f431}",                 '%F0%9F%90%B1',              'astral-plane emoji, four bytes'],
);

for my $case (@cases) {
    my ($word, $expected, $label) = @$case;
    my $escaped = $class->uri_escape($word);
    is($escaped, $expected, "$label: escapes as expected");
    ok($escaped !~ /[^\x21-\x7e]/, "$label: output is pure ASCII");
    is(pct_bytes($escaped), Encode::encode('UTF-8', $word), "$label: round trip matches the UTF-8 octets");
    is(length Encode::decode('UTF-8', pct_bytes($escaped)), length $word, "$label: character count preserved");
}

# ------------------------------------------------------------ words in requests

my ($emoji_client, $emoji_seen) = client_with({ status => 200, body => '{"word":"cat"}', content_type => 'application/json' });
$emoji_client->lookup("\x{1f431}");
is($emoji_seen->[0], 'http://api.invalid/v1/entries/en/%F0%9F%90%B1', 'an emoji word is escaped in the request path');

my ($mark_client, $mark_seen) = client_with({ status => 200, body => '{"word":"a?b#c"}', content_type => 'application/json' });
my $mark_entry = $mark_client->lookup('a?b#c');
is($mark_seen->[0], 'http://api.invalid/v1/entries/en/a%3Fb%23c', 'reserved characters stay inside the path segment');
is($mark_entry->{word}, 'a?b#c', 'the returned word is passed through unchanged');

my ($space_client, $space_seen) = client_with({ status => 200, body => '{"word":"ice cream"}', content_type => 'application/json' });
$space_client->lookup('ice cream');
is($space_seen->[0], 'http://api.invalid/v1/entries/en/ice%20cream', 'spaces in a word are escaped, not rejected');

my ($ctl_client, $ctl_seen) = client_with({ status => 200, body => '{"word":"x"}', content_type => 'application/json' });
my $ctl_error = eval { $ctl_client->lookup("a\x{1}b"); 1 } ? undef : $@;
isa_ok($ctl_error, 'Dictionary::Error', 'a control character raises an error');
is($ctl_error->kind, 'usage', 'a control character maps to usage');
is_deeply($ctl_seen, [], 'nothing was requested for a control-character word');

# ----------------------------------------------------------- responses in JSON

my $surrogate_json = '{"word":"\\ud83d\\ude00","meanings":[{"partOfSpeech":"symbol","definitions":[{"definition":"grinning face \\ud83d\\ude00"}]}]}';
my ($smile, $smile_error) = entry_for($surrogate_json, "\x{1f600}");
ok(!defined $smile_error, 'a surrogate-pair entry decodes without error');
is($smile->{word}, "\x{1f600}", 'a surrogate pair collapses into one code point');
is(length $smile->{word}, 1, 'one character, not two halves');
is(Encode::encode('UTF-8', $smile->{word}), "\xf0\x9f\x98\x80", 'the code point is U+1F600');
is($smile->{meanings}[0]{definitions}[0]{definition}, "grinning face \x{1f600}", 'unicode survives in nested strings');

my $raw_emoji_body = '{"word":"' . "\xf0\x9f\x98\x80" . '"}';
my ($raw_emoji, $raw_emoji_error) = entry_for($raw_emoji_body, 'x');
ok(!defined $raw_emoji_error, 'raw four-byte UTF-8 in the body decodes without error');
is($raw_emoji->{word}, $smile->{word}, 'raw bytes and the surrogate escape agree');

# Charset handling for bodies that are not plain UTF-8.
my ($cp1252, $cp1252_error) = entry_for(
    '{"word":"caf' . "\x80" . '"}',
    'cafe',
    'application/json; charset=windows-1252',
);
ok(!defined $cp1252_error, 'windows-1252 body decoded without error');
is($cp1252->{word}, "caf\x{20ac}", 'windows-1252 byte 0x80 is a euro sign, not a control character');

my ($quoted) = entry_for(
    '{"word":"caf' . "\xc3\xa9" . '"}',
    'cafe',
    'application/json; charset="UTF-8"',
);
is($quoted->{word}, "caf\x{e9}", 'a quoted charset parameter is honoured');

my ($mismatch) = entry_for(
    '{"word":"caf' . "\xc3\xa9" . '"}',
    'cafe',
    'application/json; charset=iso-8859-1',
);
is($mismatch->{word}, "caf\x{c3}\x{a9}", 'a mislabelled charset is obeyed, not silently repaired');
is(length $mismatch->{word}, 5, 'the mojibake is five characters, so it is visibly wrong');
isnt(Encode::encode('UTF-8', $mismatch->{word}), "caf\xc3\xa9", 'the wrong charset does not reproduce the original octets');

my $ascii_error = error_for(
    '{"word":"caf' . "\xe9" . '"}',
    'cafe',
    'application/json; charset=us-ascii',
);
isa_ok($ascii_error, 'Dictionary::Error', 'high bytes under us-ascii are rejected');
is($ascii_error->kind, 'encoding', 'a us-ascii violation maps to encoding');

# ------------------------------------------------------- unicode in neighbors

my ($uni_client, $uni_seen) = client_with({
    status       => 200,
    body         => '["caf' . "\xc3\xa9" . '","th\\u00e9"]',
    content_type => 'application/json',
});
is_deeply(
    $uni_client->neighbors('coffee'),
    ["caf\x{e9}", "th\x{e9}"],
    'unicode neighbors survive normalization from bytes and escapes',
);
is($uni_seen->[0], 'http://api.invalid/v1/neighbors/en/coffee', 'the neighbors path is unchanged for an ASCII word');

# A fresh client per request: the injected fetcher is single-use by design.
my ($self_client) = client_with({
    status       => 200,
    body         => '["caf' . "\xc3\xa9" . '"]',
    content_type => 'application/json',
});
is_deeply($self_client->neighbors("caf\x{e9}"), [], 'a unicode self word is removed from its own neighbors');

done_testing;
