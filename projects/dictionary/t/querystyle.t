use strict;
use warnings;
use Test::More;

use TestUtil;
use Dictionary::Client;
use Dictionary::Error;

my $CLASS = 'Dictionary::Client';
my $BASE  = 'http://api.invalid/v1';
my $JSON  = 'application/json';

sub entry_body     { return { status => 200, body => '{"word":"cafe"}', content_type => $JSON } }
sub neighbors_body { return { status => 200, body => '["tea"]',            content_type => $JSON } }

# Returns (client, error, requested urls).
sub build {
    my ($args, @responses) = @_;
    @responses = ({ status => 200, body => '[]', content_type => $JSON }) unless @responses;
    my ($fetcher, $seen) = recorded_fetcher(@responses);
    my $client = eval { $CLASS->new(base_url => $BASE, fetcher => $fetcher, %{ $args || {} }) };
    my $error  = $@;
    return ($client, $error, $seen);
}

# --------------------------------------------------- defaults: unchanged path

my ($default_client, $default_error, $default_seen) = build({}, entry_body(), neighbors_body());
is($default_error, '', 'a plain construction still succeeds');
isa_ok($default_client, $CLASS);
is($default_client->style,  'path',  'path is the default request style');
is($default_client->qtype,  'entry', 'qtype defaults to entry');
is($default_client->idtype, 'word',  'idtype defaults to word');

eval { $default_client->lookup('cafe') };
eval { $default_client->neighbors('cafe') };
is_deeply(
    $default_seen,
    [ "$BASE/entries/en/cafe", "$BASE/neighbors/en/cafe" ],
    'the default style emits exactly the original path URLs',
);
is(index($default_seen->[0], '?'), -1, 'path style adds no query string at all');

my ($uni_client, $uni_error, $uni_seen) = build({}, entry_body());
eval { $uni_client->lookup("caf\x{e9}") };
is($uni_seen->[0], "$BASE/entries/en/caf%C3%A9", 'path style still escapes the word once, as before');

my ($slash_client, $slash_error, $slash_seen) = build({ base_url => "$BASE/" }, entry_body());
eval { $slash_client->lookup('cafe') };
is($slash_seen->[0], "$BASE/entries/en/cafe", 'a trailing slash on base_url is still trimmed');

# ------------------------------------------------------------- query style

my ($query_client, $query_error, $query_seen) = build({ style => 'query' }, entry_body(), neighbors_body());
is($query_error, '', 'query style constructs');
is($query_client->style, 'query', 'the style accessor reports query');

eval { my $e = $query_client->lookup('cafe') };
eval { my $n = $query_client->neighbors('cafe') };
is_deeply(
    $query_seen,
    [
        "$BASE/entries?qtype=entry&idtype=word&id=cafe&lang=en",
        "$BASE/neighbors?qtype=entry&idtype=word&id=cafe&lang=en",
    ],
    'query style puts qtype, idtype, id and lang in that order',
);

my ($parsed_client, $parsed_error) = build({ style => 'query' }, entry_body());
my $parsed = eval { $parsed_client->lookup('cafe') };
is(ref $parsed ? $parsed->{word} : '(no entry)', 'cafe', 'a query-style response parses like a path-style one');

my ($nb_client, $nb_error, $nb_seen) = build({ style => 'query' }, neighbors_body());
eval { my $w = $nb_client->neighbors("caf\x{e9}") };
is($nb_seen->[0], "$BASE/neighbors?qtype=entry&idtype=word&id=caf%C3%A9&lang=en", 'neighbors uses the same query shape and escapes the word once');

my ($custom_client, $custom_error, $custom_seen) = build(
    { style => 'query', lang => 'zh-Hant', qtype => 'definition', idtype => 'headword' },
    entry_body(),
);
is($custom_error, '', 'a customised query style constructs');
is($custom_client->qtype,  'definition', 'the qtype accessor reports the configured value');
is($custom_client->idtype, 'headword',   'the idtype accessor reports the configured value');
eval { my $e = $custom_client->lookup('cafe') };
is($custom_seen->[0], "$BASE/entries?qtype=definition&idtype=headword&id=cafe&lang=zh-Hant", 'configured qtype, idtype and lang all land in the query');

# Every value is percent-encoded, so nothing in the id can break out.
my ($res_client, $res_error, $res_seen) = build({ style => 'query' }, entry_body());
eval { my $e = $res_client->lookup('a&b=c') };
is($res_seen->[0], "$BASE/entries?qtype=entry&idtype=word&id=a%26b%3Dc&lang=en", 'an ampersand or equals in the id cannot inject a parameter');

my ($space_client, $space_error, $space_seen) = build({ style => 'query' }, entry_body());
eval { my $e = $space_client->lookup('ice cream') };
is($space_seen->[0], "$BASE/entries?qtype=entry&idtype=word&id=ice%20cream&lang=en", 'a space in the id is %20, never a plus');

my ($pct_client, $pct_error, $pct_seen) = build({ style => 'query' }, entry_body());
eval { my $e = $pct_client->lookup('100%') };
is($pct_seen->[0], "$BASE/entries?qtype=entry&idtype=word&id=100%25&lang=en", 'a literal percent sign in the id is escaped, not passed raw');

my ($q_client, $q_error, $q_seen) = build({ style => 'query' }, entry_body());
eval { my $e = $q_client->lookup('a?b#c') };
is($q_seen->[0], "$BASE/entries?qtype=entry&idtype=word&id=a%3Fb%23c&lang=en", 'query and fragment marks stay inside the id value');

# A path style client never lets qtype/idtype leak into the URL.
my ($ignore_client, $ignore_error, $ignore_seen) = build({ qtype => 'definition', idtype => 'headword' }, entry_body());
is($ignore_error, '', 'qtype and idtype are accepted with the default style');
eval { my $e = $ignore_client->lookup('cafe') };
is($ignore_seen->[0], "$BASE/entries/en/cafe", 'qtype and idtype do not appear in a path-style URL');

# ------------------------------------------------------- accepted identifiers

my @good_ident = ('entry', 'definition', 'word', 'A', 'a', 'e_1', 'abc123', 'a' x 32);
for my $value (@good_ident) {
    for my $param (qw(qtype idtype)) {
        my ($client, $error, $seen) = build({ $param => $value });
        is($error, '', "$param '$value' accepted");
        is($client ? $client->$param : '<<construction failed>>', $value, "$param '$value' kept verbatim");
        is_deeply($seen, [], "no request made while constructing $param '$value'");
    }
}

# ------------------------------------------------------- rejected identifiers

my @bad_ident = (
    [ '',               'empty string' ],
    [ '1entry',         'leading digit' ],
    [ 'entry-x',        'hyphen' ],
    [ 'entry.x',        'dot' ],
    [ 'ent ry',         'embedded space' ],
    [ 'entry ',         'trailing space' ],
    [ "ent\x{e9}ry",    'non-ASCII character' ],
    [ "entry\n",        'trailing newline' ],
    [ 'a' x 33,         'thirty-three characters' ],
);

for my $case (@bad_ident) {
    my ($value, $label) = @$case;
    for my $param (qw(qtype idtype)) {
        my ($client, $error, $seen) = build({ $param => $value });
        is(ref $error, 'Dictionary::Error', "$param rejected as an error object: $label");
        is(ref($error) ? $error->kind : 'not-an-error', 'usage', "$param '$label' maps to usage");
        my $message = ref($error) ? $error->message : "$error";
        like($message, qr/\b$param\b/, "message names the $param parameter: $label");
        unlike($message, qr/\n/, "message stays on one line: $label");
        is_deeply($seen, [], "no request attempted for $param '$label'");
        ok(!defined $client, "no client object built for $param '$label'");
    }
}

for my $case ([ [], 'an array reference' ], [ {}, 'a hash reference' ]) {
    my ($value, $label) = @$case;
    for my $param (qw(qtype idtype)) {
        my ($client, $error, $seen) = build({ $param => $value });
        is(ref $error, 'Dictionary::Error', "$param $label rejected");
        is(ref($error) ? $error->kind : 'not-an-error', 'usage', "$param $label maps to usage");
        is_deeply($seen, [], "no request for $param $label");
    }
}

# ------------------------------------------------------------- accepted style

for my $style (qw(path query)) {
    my ($client, $error, $seen) = build({ style => $style });
    is($error, '', "style '$style' accepted");
    is($client ? $client->style : '<<construction failed>>', $style, "style '$style' kept verbatim");
    is_deeply($seen, [], "no request made while constructing style '$style'");
}

# ------------------------------------------------------------- rejected style

my @bad_style = (
    [ '',             'empty string' ],
    [ 'PATH',         'uppercase' ],
    [ 'query ',       'trailing space' ],
    [ ' query',       'leading space' ],
    [ 'querystring',  'unknown name' ],
    [ 'path?query',   'punctuation' ],
    [ "query\n",      'trailing newline' ],
);

for my $case (@bad_style) {
    my ($style, $label) = @$case;
    my ($client, $error, $seen) = build({ style => $style });
    is(ref $error, 'Dictionary::Error', "style rejected as an error object: $label");
    is(ref($error) ? $error->kind : 'not-an-error', 'usage', "style '$label' maps to usage");
    my $message = ref($error) ? $error->message : "$error";
    like($message, qr/\bstyle\b/, "message names the style parameter: $label");
    unlike($message, qr/\n/, "message stays on one line: $label");
    is_deeply($seen, [], "no request attempted for style '$label'");
    ok(!defined $client, "no client object built for style '$label'");
}

for my $case ([ [], 'an array reference' ], [ {}, 'a hash reference' ]) {
    my ($value, $label) = @$case;
    my ($client, $error, $seen) = build({ style => $value });
    is(ref $error, 'Dictionary::Error', "style $label rejected");
    is(ref($error) ? $error->kind : 'not-an-error', 'usage', "style $label maps to usage");
    is_deeply($seen, [], "no request for style $label");
}

# ------------------------------------------------------- undef keeps defaults

my ($undef_style_client, $undef_style_error) = build({ style => undef });
is($undef_style_error, '', 'style => undef does not fail');
is($undef_style_client ? $undef_style_client->style : '<<failed>>', 'path', 'undef style falls back to path');

my ($undef_ident_client, $undef_ident_error) = build({ qtype => undef, idtype => undef });
is($undef_ident_error, '', 'qtype/idtype => undef does not fail');
is($undef_ident_client ? $undef_ident_client->qtype  : '<<failed>>', 'entry', 'undef qtype falls back to entry');
is($undef_ident_client ? $undef_ident_client->idtype : '<<failed>>', 'word',  'undef idtype falls back to word');

# ------------------------------------------- words are still checked first

my ($word_client, $word_error, $word_seen) = build({ style => 'query' }, entry_body(), entry_body());
for my $word ('', '   ', 'a/b', "a\x{1}b") {
    my $error = eval { $word_client->lookup($word); 1 } ? undef : $@;
    is(ref $error ? $error->kind : 'no error', 'usage', 'query style still refuses a bad word before any URL exists');
}
is_deeply($word_seen, [], 'no query URL was built for a rejected word');

done_testing;
