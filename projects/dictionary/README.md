# dictionary

A small Perl client for a JSON dictionary HTTP API, plus a thin CLI.

## Status: assumptions, not a confirmed contract

No API contract for this service was confirmed in-channel, so nothing below is
claimed to be a real, verified endpoint. Everything unverified is **stubbed
behind one seam** (`Dictionary::Client`) and documented here. If the real API
differs, you change field names in `normalize_entry`/`neighbors` and the two
path strings in `_entries`/`neighbors` -- nothing else.

### Assumed API (UNCONFIRMED -- treat as a stub contract)

Base URL: `DICTIONARY_API_BASE` env var, else the constructor `base_url`,
else `https://api.dictionary.invalid/v1` (deliberately a reserved, unroutable
name so a misconfiguration fails loudly instead of hitting a random host).

1. `GET {base}/entries/{lang}/{word}`
   Returns a JSON **array** of entry objects. A single object is also accepted.
   Entry fields used: `word`, `phonetic`, `origin`,
   `phonetics[].audio`, `meanings[].partOfSpeech`,
   `meanings[].definitions[].{definition,example,synonyms,antonyms}`,
   plus optional `meanings[].synonyms|antonyms`.
   (`part_of_speech` is accepted as a snake_case fallback.)
2. `GET {base}/neighbors/{lang}/{word}`
   Returns a JSON **array** of related words: either bare strings or objects
   with a `word` key. This endpoint name is a guess; it is the most
   speculative part of the client.
3. Status handling: `200-299` parsed; `404` -> `not_found`; `429` ->
   `rate_limited`; `5xx` -> `server`; any other non-2xx -> `http`.
   A `2xx` with an empty array, `null`, or no usable objects -> `not_found`.
4. Charset: taken from the `Content-Type` header, default `UTF-8`.
   `utf-8`/`utf8`, `us-ascii`/`ascii`, `iso-8859-1`/`latin1`, `windows-1252`
   map to Encode names. An unknown charset is an `encoding` error, not a guess.
5. Query words are UTF-8 percent-encoded. Words containing `/`, `\`, NUL or
   control characters are rejected (`usage`) rather than escaped, so a word
   can never inject an extra path segment.
6. No authentication, no pagination, no caching, no retry logic: unimplemented.

### What is stubbed

`Dictionary::Client::_http_fetcher` is the only code that touches the network
(HTTP::Tiny, core). Every test injects a fake fetcher, so the suite is fully
offline and deterministic. The real transport path is therefore **not covered
by tests** and neither is `bin/dict`; both are documented as untested.

## Usage

    my $client = Dictionary::Client->new(base_url => 'https://example/v1');
    my $entry  = $client->lookup('cafe');        # dies on Dictionary::Error
    my $all    = $client->lookup_all('cafe');    # arrayref of normalized entries
    my $words  = $client->neighbors('cafe');     # arrayref of strings

Errors are `Dictionary::Error` objects with `kind`, `message`, optional
`status`. Kinds: `usage`, `network`, `encoding`, `parse`, `not_found`,
`rate_limited`, `server`, `http`.

CLI:

    perl -Ilib bin/dict cafe
    perl -Ilib bin/dict --neighbors cafe

## Tests

    perl run-tests.pl

Runs every `t/*.t` in a fresh interpreter against `t/fixtures/*.json`.
Covered: entry parsing (including two meanings and UTF-8 text), request URL
encoding, neighbors dedupe/self-removal/limit, missing entries (404, empty
array, null), error mapping (500/429/403, bad JSON, invalid UTF-8, unknown
charset, transport failure, dying fetcher), and encoding equivalence between
`\u` escapes and raw UTF-8 bytes.

`t/unicode.t` adds the character-level matrix on top of that: the full RFC 3986
reserved set (including `%`, `?`, `#`, `&`, `=` and `+`), space, plus-sign and
DEL handling, multi-byte scripts (Latin-1 accents, CJK, Cyrillic, astral-plane
emoji), combining marks, percent-encoding round trips back to the original
UTF-8 octets, JSON surrogate pairs, raw four-byte body text, and
`windows-1252`/quoted-charset header handling including a deliberately
mislabelled body that must mojibake rather than be silently repaired.
