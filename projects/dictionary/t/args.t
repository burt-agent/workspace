use strict;
use warnings;
use Test::More;

use Dictionary::Client;
use Dictionary::Error;

my $CLASS = 'Dictionary::Client';

# Records every URL it is asked for. Constructor validation must never reach
# the transport, so any request seen here is a bug.
sub watched_fetcher {
    my ($response) = @_;
    my @seen;
    my $fetcher = sub {
        my ($url) = @_;
        push @seen, $url;
        return $response;
    };
    return ($fetcher, \@seen);
}

# Returns (client, error, requested urls).
sub construct {
    my (%arg) = @_;
    my ($fetcher, $seen) = watched_fetcher({ status => 200, body => '[]', content_type => 'application/json' });
    $arg{fetcher} = $fetcher unless exists $arg{fetcher};
    my $client = eval { $CLASS->new(base_url => 'http://api.invalid/v1', %arg) };
    my $error = $@;
    return ($client, $error, $seen);
}

sub kept_lang {
    my ($client) = @_;
    return $client ? $client->lang : '<<construction failed>>';
}

# -------------------------------------------------------------- accepted lang

my @valid_lang = (
    [ 'en',          'two-letter primary subtag' ],
    [ 'EN',          'uppercase letters are still ASCII letters' ],
    [ 'a',           'one letter, the minimum length' ],
    [ 'abcdefgh',    'eight letters, the maximum length' ],
    [ 'en-US',       'region subtag' ],
    [ 'zh-Hant',     'script subtag' ],
    [ 'ab-12345678', 'eight character alphanumeric subtag' ],
    [ 'en-US-x-1',   'several hyphenated subtags' ],
);

for my $case (@valid_lang) {
    my ($lang, $label) = @$case;
    my ($client, $error, $seen) = construct(lang => $lang);
    is($error, '', "lang '$lang' accepted: $label");
    is(kept_lang($client), $lang, "lang '$lang' kept verbatim");
    is_deeply($seen, [], "no request made while constructing lang '$lang'");
}

my ($tagged_client, $tagged_error, $tagged_seen) = construct(lang => 'zh-Hant');
is($tagged_error, '', 'a script-subtag lang constructs without error');
is_deeply($tagged_client->neighbors('seed'), [], 'a validated lang is usable for a request');
is($tagged_seen->[0], 'http://api.invalid/v1/neighbors/zh-Hant/seed', 'the validated lang lands in the request path');

# -------------------------------------------------------------- rejected lang

my @invalid_lang = (
    [ '',                'empty string' ],
    [ 'en_US',           'underscore instead of hyphen' ],
    [ 'en-',             'trailing hyphen leaves an empty subtag' ],
    [ '-en',             'leading hyphen' ],
    [ 'en--US',          'double hyphen leaves an empty subtag' ],
    [ 'abcdefghi',       'nine letters in the primary subtag' ],
    [ 'en-US-123456789', 'nine characters in a later subtag' ],
    [ 'en1',             'digit in the primary subtag' ],
    [ 'en US',           'space inside the tag' ],
    [ ' en',             'leading space' ],
    [ 'en ',             'trailing space' ],
    [ 'en/us',           'slash' ],
    [ 'en-#',            'non-alphanumeric subtag' ],
    [ "caf\x{e9}",       'non-ASCII character' ],
    [ "en\nUS",          'embedded newline' ],
);

for my $case (@invalid_lang) {
    my ($lang, $label) = @$case;
    my ($client, $error, $seen) = construct(lang => $lang);
    is(ref $error, 'Dictionary::Error', "lang rejected as an error object: $label");
    is(ref($error) ? $error->kind : 'not-an-error', 'usage', "lang '$label' maps to usage");
    my $message = ref($error) ? $error->message : "$error";
    like($message, qr/\blang\b/, "message names the lang parameter: $label");
    unlike($message, qr/\n/, "message stays on one line: $label");
    is_deeply($seen, [], "no request attempted for lang '$label'");
    ok(!defined $client, "no client object built for lang '$label'");
}

for my $case ([ [], 'an array reference' ], [ {}, 'a hash reference' ]) {
    my ($value, $label) = @$case;
    my ($client, $error, $seen) = construct(lang => $value);
    is(ref $error, 'Dictionary::Error', "lang $label rejected");
    is(ref($error) ? $error->kind : 'not-an-error', 'usage', "lang $label maps to usage");
    is_deeply($seen, [], "no request for lang $label");
}

my ($ignored_client, $lang_error) = construct(lang => 'en_US');
like("$lang_error", qr/^usage:/, 'a bad lang stringifies as a usage error');

# -------------------------------------------------- accepted max_neighbors

my @valid_max = (
    [ 0,    'zero disables the cap' ],
    [ 1,    'one' ],
    [ 25,   'the default value' ],
    [ 100,  'a larger cap' ],
    [ '7',  'a numeric string' ],
    [ '0',  'zero as a string' ],
);

for my $case (@valid_max) {
    my ($max, $label) = @$case;
    my ($client, $error, $seen) = construct(max_neighbors => $max);
    is($error, '', "max_neighbors '$max' accepted: $label");
    isa_ok($client, $CLASS);
    is_deeply($seen, [], "no request made while constructing max_neighbors '$max'");
}

# -------------------------------------------------- rejected max_neighbors

my @invalid_max = (
    [ -1,      'negative integer' ],
    [ 1.5,     'fractional number' ],
    [ '',      'empty string' ],
    [ '3x',    'trailing garbage' ],
    [ ' 3',    'leading space' ],
    [ '3 ',    'trailing space' ],
    [ '1e3',   'exponent notation' ],
    [ '-1',    'negative numeric string' ],
    [ '+1',    'explicit plus sign' ],
    [ '0x10',  'hex literal' ],
    [ '1_000', 'underscore separator' ],
    [ 'three', 'a word' ],
);

for my $case (@invalid_max) {
    my ($max, $label) = @$case;
    my ($client, $error, $seen) = construct(max_neighbors => $max);
    is(ref $error, 'Dictionary::Error', "max_neighbors rejected as an error object: $label");
    is(ref($error) ? $error->kind : 'not-an-error', 'usage', "max_neighbors '$label' maps to usage");
    my $message = ref($error) ? $error->message : "$error";
    like($message, qr/max_neighbors/, "message names the max_neighbors parameter: $label");
    unlike($message, qr/\n/, "message stays on one line: $label");
    is_deeply($seen, [], "no request attempted for max_neighbors '$label'");
    ok(!defined $client, "no client object built for max_neighbors '$label'");
}

for my $case ([ [], 'an array reference' ], [ {}, 'a hash reference' ]) {
    my ($value, $label) = @$case;
    my ($client, $error, $seen) = construct(max_neighbors => $value);
    is(ref $error, 'Dictionary::Error', "max_neighbors $label rejected");
    is(ref($error) ? $error->kind : 'not-an-error', 'usage', "max_neighbors $label maps to usage");
    is_deeply($seen, [], "no request for max_neighbors $label");
}

# -------------------------------------------------- defaults still preserved

my @many = map { "w$_" } 1 .. 30;
my $many_body = '[' . join(',', map { qq{"$_"} } @many) . ']';

my ($default_fetcher, $default_seen) = watched_fetcher(
    { status => 200, body => $many_body, content_type => 'application/json' },
);
my $defaulted = $CLASS->new(base_url => 'http://api.invalid/v1', fetcher => $default_fetcher);
is($defaulted->lang, 'en', 'omitted lang still defaults to en');
is_deeply(
    $defaulted->neighbors('seed'),
    [ @many[ 0 .. 24 ] ],
    'omitted max_neighbors still defaults to 25',
);
is($default_seen->[0], 'http://api.invalid/v1/neighbors/en/seed', 'the default lang is used in the request path');

my ($undef_lang_client) = construct(lang => undef);
is(kept_lang($undef_lang_client), 'en', 'undef lang falls back to the default');

my ($uncapped_fetcher) = watched_fetcher(
    { status => 200, body => $many_body, content_type => 'application/json' },
);
my $uncapped = $CLASS->new(base_url => 'http://api.invalid/v1', fetcher => $uncapped_fetcher, max_neighbors => undef);
is(scalar @{ $uncapped->neighbors('seed') }, 30, 'undef max_neighbors still means no cap');

my ($capped_fetcher) = watched_fetcher(
    { status => 200, body => $many_body, content_type => 'application/json' },
);
my $capped = $CLASS->new(base_url => 'http://api.invalid/v1', fetcher => $capped_fetcher, max_neighbors => 3);
is_deeply($capped->neighbors('seed'), [ @many[ 0 .. 2 ] ], 'a validated cap is still applied');

my ($zero_fetcher) = watched_fetcher(
    { status => 200, body => $many_body, content_type => 'application/json' },
);
my $zero_cap = $CLASS->new(base_url => 'http://api.invalid/v1', fetcher => $zero_fetcher, max_neighbors => 0);
is_deeply($zero_cap->neighbors('seed'), [], 'a validated zero cap still yields an empty list');

# ---------------------------------- validation wins over the injected fetcher

my ($injected_fetcher, $injected_seen) = watched_fetcher(
    { status => 200, body => '[]', content_type => 'application/json' },
);
my $bad = eval { $CLASS->new(base_url => 'http://api.invalid/v1', fetcher => $injected_fetcher, lang => 'en_US') };
is(ref $bad, '', 'a bad lang dies even with a fetcher injected');
is_deeply($injected_seen, [], 'the injected fetcher was never called');

my $bad_max = eval { $CLASS->new(base_url => 'http://api.invalid/v1', fetcher => $injected_fetcher, max_neighbors => -5) };
is(ref $bad_max, '', 'a bad max_neighbors dies even with a fetcher injected');
is_deeply($injected_seen, [], 'the injected fetcher is still untouched after a second bad construction');

done_testing;
