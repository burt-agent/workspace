# dictionary

A small Perl client for a JSON dictionary HTTP API, plus a thin CLI.

## Status: assumptions, not a confirmed contract

No API contract for this service was confirmed in-channel, so nothing below is
claimed to be a real, verified endpoint. Everything unverified is **stubbed
behind one seam** (`Dictionary::Client`) and documented here. If the real API
differs, you change field names in `normalize_entry`/`neighbors` and the URL
builder `_request_path` -- nothing else.

### Assumed API (UNCONFIRMED -- treat as a stub contract)

Base URL: `DICTIONARY_API_BASE` env var, else the constructor `base_url`,
else `https://api.dictionary.invalid/v1` (deliberately a reserved, unroutable
name so a misconfiguration fails loudly instead of hitting a random host).

1. Path style (the default): `GET {base}/entries/{lang}/{word}` and
   `GET {base}/neighbors/{lang}/{word}`.
2. Query style (`style => 'query'`): `GET {base}/entries?qtype=&idtype=&id=&lang=`
   and the same four parameters on `/neighbors`, always in that order.
3. Entries are a JSON **array** of objects; a single object is also accepted.
   Entry fields used: `word`, `phonetic`, `origin`, `phonetics[].audio`,
   `meanings[].partOfSpeech`,
   `meanings[].definitions[].{definition,example,synonyms,antonyms}`,
   plus optional `meanings[].synonyms|antonyms`.
   (`part_of_speech` is accepted as a snake_case fallback.)
4. Neighbors are a JSON **array** of related words: either bare strings or
   objects with a `word` key. This endpoint name is a guess; it is the most
   speculative part of the client.
5. Status handling: `200-299` parsed; `404` -> `not_found`; `429` ->
   `rate_limited`; `5xx` -> `server`; any other non-2xx -> `http`.
   A `2xx` with an empty array, `null`, or no usable objects -> `not_found`.
6. Charset: taken from the `Content-Type` header, default `UTF-8`.
   `utf-8`/`utf8`, `us-ascii`/`ascii`, `iso-8859-1`/`latin1`, `windows-1252`
   map to Encode names. An unknown charset is an `encoding` error, not a guess.
7. Every URL value is UTF-8 percent-encoded. Words containing `/`, backslash,
   NUL or control characters are rejected (`usage`) rather than escaped, so a
   word can never inject an extra path segment or query parameter.
8. No authentication, no pagination, no caching, no retry logic: unimplemented.

### What is stubbed

`Dictionary::Client::_http_fetcher` is the only code that touches the network
(HTTP::Tiny, core). Every test injects a fake fetcher, so the suite is fully
offline and deterministic. The real transport path is therefore **not covered
by tests**, and neither is `bin/dict`; both are documented as untested.

## Usage

    my $client = Dictionary::Client->new(base_url => 'https://example/v1');
    my $entry  = $client->lookup('cafe');         # dies on Dictionary::Error
    my $all    = $client->lookup_all('cafe');     # arrayref of normalized entries
    my $words  = $client->neighbors('cafe');      # arrayref of strings

Errors are `Dictionary::Error` objects with `kind`, `message`, optional
`status`. Kinds: `usage`, `network`, `encoding`, `parse`, `not_found`,
`rate_limited`, `server`, `http`.

CLI (`bin/dict` keeps its original single flag; the query style is a library
option, not a CLI flag):

    perl -Ilib bin/dict cafe
    perl -Ilib bin/dict --neighbors cafe

To use the query style, construct the client directly -- see below.

## Request styles: `path` (default) and `query`

The original request shape is the default and is byte-for-byte unchanged:

    GET {base}/entries/{lang}/{word}
    GET {base}/neighbors/{lang}/{word}

`style => 'query'` moves every value into the query string instead, in a fixed
order -- `qtype`, `idtype`, `id`, `lang`:

    GET {base}/entries?qtype=entry&idtype=word&id=cafe&lang=en
    GET {base}/neighbors?qtype=entry&idtype=word&id=cafe&lang=en

The parameter *names* come from `qtype` and `idtype` (defaults `entry` and
`word`), so a service that wants `qtype=definition&idtype=headword` gets it from
constructor arguments rather than from a second code path:

    my $client = Dictionary::Client->new(style  => 'query',
                                        qtype  => 'definition',
                                        idtype => 'headword');

Every value is escaped with the same `uri_escape` used for path segments, so an
id such as `a&b=c` becomes `id=a%26b%3Dc` and cannot inject a parameter; a space
is `%20`, never `+`. `qtype` and `idtype` are additionally validated as ASCII
identifiers -- a letter followed by up to 31 letters, digits or underscores --
because they are part of the assumed contract, not free-form text. With the
default `path` style the two identifiers are accepted and validated but never
appear in a URL.

Anything else for `style` -- `'PATH'`, `'query '`, `'querystring'`, a reference,
an embedded newline -- is a `usage` error raised from the constructor, before
any transport exists. Both styles share response parsing, status handling,
charset decoding and neighbor normalization, so switching styles changes only
the URL.

## Constructor validation

`new` validates its arguments before it stores anything, and it does so even
when a `fetcher` is injected, so a bad constructor argument can never reach the
transport. Every failure raises `Dictionary::Error` with kind `usage`, and the
message names the offending parameter. The value is shown with control
characters and non-ASCII bytes escaped, so the message stays on one line.

`lang` must be 1-8 ASCII letters, then optional hyphen-separated 1-8 character
alphanumeric subtags (`en`, `en-US`, `zh-Hant`).

- Accepted: `en`, `EN`, `a`, `abcdefgh`, `en-US`, `zh-Hant`, `ab-12345678`,
  `en-US-x-1`.
- Rejected: `''`, `en_US`, `en-`, `-en`, `en--US`, `en1` (digit in the
  primary subtag), `abcdefghi` and `en-US-123456789` (9 character subtags),
  `en US` / `' en'` / `'en '` (spaces), `en/us`, `en-#`, a non-ASCII accented
  `cafe`, embedded newlines, and references.

`max_neighbors` must be `undef` or a nonnegative integer.

- Accepted: `undef` (no cap), `0`, `1`, `25`, `100`, `'7'`, `'0'`.
- Rejected: `-1`, `1.5`, `''`, `'3x'`, `' 3'`, `'3 '`, `'-1'`, `'+1'`,
  `'1e3'`, `'0x10'`, `'1_000'`, and references.

`style` must be `path` or `query`.

- Accepted: `path`, `query`.
- Rejected: `''`, `PATH`, `'query '`, `' query'`, `querystring`, `path?query`,
  embedded newlines, and references.

`qtype` and `idtype` must be ASCII identifiers as described above.

- Accepted: `entry`, `definition`, `word`, `A`, `a`, `e_1`, `abc123`, and a
  32-character identifier.
- Rejected: `''`, `1entry`, `entry-x`, `entry.x`, `'ent ry'`, `'entry '`,
  non-ASCII characters, embedded newlines, a 33-character identifier, and
  references.

Omitting an argument, or passing `undef`, still means the defaults:
`lang => 'en'`, `max_neighbors => 25`, `style => 'path'`, `qtype => 'entry'`,
`idtype => 'word'`. `lang => undef` falls back to `'en'`; `max_neighbors => undef`
keeps meaning "no cap", as it always has.

## Tests

    perl run-tests.pl

Runs every `t/*.t` in a fresh interpreter against `t/fixtures/*.json`.
Covered: entry parsing (including two meanings and UTF-8 text), request URL
encoding, neighbors dedupe/self-removal/limit, missing entries (404, empty
array, null), error mapping (500/429/403, bad JSON, invalid UTF-8, unknown
charset, transport failure, dying fetcher), and encoding equivalence between
JSON escapes and raw UTF-8 bytes.

`t/args.t` covers the constructor contract: every accepted and rejected `lang`
and `max_neighbors` form, the `usage` kind, the message naming the parameter
and staying unbroken by control characters, the fact that no request is made
for a rejected argument, and that the defaults survive both omission and an
explicit `undef`.

`t/querystyle.t` covers the request styles: that `path` still emits exactly the
original URLs with no query string at all, that `query` emits
`qtype`, `idtype`, `id`, `lang` in that order for both resources, that
configured `qtype`/`idtype`/`lang` values land in the query, that ampersand,
equals, percent, question mark, hash and spaces in the id stay inside the value,
that `qtype`/`idtype` never leak into a path-style URL, every accepted and
rejected identifier and style form, `undef` falling back to the defaults, and
that a bad word is still refused before any URL is built.

`t/unicode.t` adds the character-level matrix on top of that: the full RFC 3986
reserved set (including percent, question mark, hash, ampersand, equals and
plus), space, plus-sign and DEL handling, multi-byte scripts (Latin-1 accents,
CJK, Cyrillic, astral-plane emoji), combining marks, percent-encoding round
trips back to the original UTF-8 octets, JSON surrogate pairs, raw four-byte
body text, and `windows-1252`/quoted-charset header handling including a
deliberately mislabelled body that must mojibake rather than be silently
repaired.
