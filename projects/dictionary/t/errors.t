use strict;
use warnings;
use Test::More;

use TestUtil;
use Dictionary::Client;
use Dictionary::Error;

sub error_for_neighbors {
    my ($response) = @_;
    my ($fetcher, $seen) = recorded_fetcher($response);
    my $client = Dictionary::Client->new(base_url => 'http://api.invalid/v1', fetcher => $fetcher);
    return eval { $client->neighbors('word'); 1 } ? undef : $@;
}

my $server = error_for_neighbors({ status => 500, body => 'oops', content_type => 'text/plain' });
isa_ok($server, 'Dictionary::Error', '500 raises Dictionary::Error');
is($server->kind, 'server', '5xx maps to server');
is($server->status, 500, '500 status preserved');
like("$server", qr/server/, 'stringifies with the error kind');

my $unavailable = error_for_neighbors({ status => 503, body => '' });
is($unavailable->kind, 'server', '503 maps to server');
is($unavailable->status, 503, '503 status preserved');

my $limited = error_for_neighbors({ status => 429, body => '' });
is($limited->kind, 'rate_limited', '429 maps to rate_limited');
is($limited->status, 429, '429 status preserved');

is(error_for_neighbors({ status => 403, body => '' })->kind, 'http', '403 maps to http');
is(error_for_neighbors({ status => 302, body => '' })->kind, 'http', '3xx maps to http');
is(error_for_neighbors({ status => 400, body => '' })->kind, 'http', '400 maps to http');

my $bad_json = error_for_neighbors({ status => 200, body => '{not json', content_type => 'application/json' });
is($bad_json->kind, 'parse', 'malformed JSON maps to parse');
like($bad_json->message, qr/api\.invalid/, 'parse error names the URL');

my $bad_bytes = error_for_neighbors({ status => 200, body => "[\"caf\xc3\x28\"]", content_type => 'application/json; charset=utf-8' });
is($bad_bytes->kind, 'encoding', 'invalid UTF-8 maps to encoding');

my $bad_charset = error_for_neighbors({ status => 200, body => '["x"]', content_type => 'application/json; charset=klingon' });
is($bad_charset->kind, 'encoding', 'unknown charset maps to encoding');
like($bad_charset->message, qr/klingon/, 'encoding error names the bad charset');

my $ascii_body = error_for_neighbors({ status => 200, body => "[\"caf\xe9\"]", content_type => 'application/json; charset=us-ascii' });
is($ascii_body->kind, 'encoding', 'high bytes in a us-ascii body map to encoding');

my $transport = error_for_neighbors({ status => 599, body => '', transport_error => 'connect timeout' });
is($transport->kind, 'network', 'transport_error maps to network');
like($transport->message, qr/connect timeout/, 'network error keeps the transport detail');

my $dies = error_for_neighbors(sub { die "socket closed\n" });
is($dies->kind, 'network', 'a dying fetcher maps to network');
like($dies->message, qr/socket closed/, 'network error keeps the fetcher detail');

my $undef_response = error_for_neighbors(sub { return undef });
is($undef_response->kind, 'network', 'a fetcher returning nothing maps to network');

my $non_hash = error_for_neighbors(sub { return 'nonsense' });
is($non_hash->kind, 'network', 'a non-hash response maps to network');

# A non-UTF-8 charset that IS supported must decode cleanly rather than error.
my ($latin1_fetcher, $latin1_seen) = recorded_fetcher(
    { status => 200, body => "[\"caf\xe9\"]", content_type => 'application/json; charset=iso-8859-1' },
);
my $latin1_client = Dictionary::Client->new(base_url => 'http://api.invalid/v1', fetcher => $latin1_fetcher);
is_deeply($latin1_client->neighbors('cafe'), ["caf\x{e9}"], 'iso-8859-1 body decodes instead of erroring');
is_deeply($latin1_seen, ['http://api.invalid/v1/neighbors/en/cafe'], 'neighbors URL built without a trailing slash problem');

done_testing;
