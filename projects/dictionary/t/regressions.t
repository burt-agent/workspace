use strict;
use warnings;
use Test::More;

use Dictionary::Client;
use Dictionary::Error;

my @seen;

sub run {
    my ($method, $word, $body, $type) = @_;
    @seen = ();
    $body = '[]' unless defined $body;
    my $client = Dictionary::Client->new(base_url => 'http://api.invalid/v1',
        fetcher => sub {
            push @seen, $_[0];
            return { status => 200, body => $body,
                     content_type => $type || 'application/json' };
        });
    my ($value, $error);
    if (eval { $value = $client->$method($word); 1 }) { } else { $error = $@ }
    return ($value, $error);
}

sub kind {
    my ($error) = @_;
    return 'none'   unless defined $error;
    return 'broken' unless ref $error && $error->isa('Dictionary::Error');
    return $error->kind;
}

# blank and slash-bearing words are refused before any URL exists
for my $word ('', '   ', 'a/b', '/a') {
    for my $method (qw(lookup lookup_all neighbors)) {
        my ($value, $error) = run($method, $word);
        is(kind($error), 'usage', "$method refuses '$word'");
        is_deeply(\@seen, [], "$method sends nothing for '$word'");
    }
}

# malformed JSON is a parse error with no HTTP status and one attempt
for my $body ('{not json', '', '["a",]') {
    my $tag = length $body ? unpack('H*', $body) : 'empty';
    my ($value, $error) = run('lookup', 'cafe', $body);
    is(kind($error), 'parse', "malformed JSON $tag is a parse error");
    is(ref $error ? $error->status : 'status', undef, "malformed JSON $tag has no status");
    is(scalar @seen, 1, "malformed JSON $tag made exactly one request");
}

# UTF-8 and other charsets in the response body
my $utf8 = '{"word":"caf' . "\xc3\xa9" . '"}';
my ($u, $ue) = run('lookup', 'cafe', $utf8, 'application/json; charset=UTF-8');
is(kind($ue), 'none', 'a UTF-8 body is accepted');
is(ref $u ? $u->{word} : '', "caf\x{e9}", 'a UTF-8 body decodes to characters');

my ($c, $ce) = run('lookup', 'cafe', '{"word":"caf' . "\x80" . '"}',
    'application/json; charset=windows-1252');
is(kind($ce), 'none', 'a windows-1252 body is accepted');
is(ref $c ? $c->{word} : '', "caf\x{20ac}", 'windows-1252 byte 0x80 is a euro sign');

my ($b, $be) = run('lookup', 'cafe', '["caf' . "\xc3\x28" . '"]',
    'application/json; charset=utf-8');
is(kind($be), 'encoding', 'invalid UTF-8 is an encoding error');
is_deeply(\@seen, ['http://api.invalid/v1/entries/en/cafe'], 'the encoding error still used one URL');

done_testing;
