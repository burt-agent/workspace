package Dictionary::Client;
use strict;
use warnings;

use Encode ();
use JSON::PP ();
use Dictionary::Error ();

our $VERSION = '0.08';

# Charset names accepted in Content-Type. Anything else is an error, not a guess.
my %CHARSET = (
    'utf-8'         => 'UTF-8',
    'utf8'          => 'UTF-8',
    'us-ascii'      => 'US-ASCII',
    'ascii'         => 'US-ASCII',
    'iso-8859-1'    => 'ISO-8859-1',
    'latin1'        => 'ISO-8859-1',
    'latin-1'       => 'ISO-8859-1',
    'windows-1252'  => 'cp1252',
    'cp1252'        => 'cp1252',
);

# A language tag: 1-8 ASCII letters, then optional hyphen-separated 1-8
# character alphanumeric subtags ('en', 'en-US', 'zh-Hant').
my $LANG_RE = qr/\A[A-Za-z]{1,8}(?:-[A-Za-z0-9]{1,8})*\z/;

# How a request addresses a word. 'path' is the original, unchanged shape.
my @STYLES = qw(path query);
my %STYLE  = map { $_ => 1 } @STYLES;

# qtype/idtype are ASCII identifiers: a letter, then up to 31 letters, digits
# or underscores. They are never used raw in a URL anyway -- both are
# percent-encoded -- but a fixed alphabet keeps the assumed contract honest.
my $IDENT_RE = qr/\A[A-Za-z][A-Za-z0-9_]{0,31}\z/;

sub new {
    my ($class, %arg) = @_;

    # Every argument is validated before anything is stored or fetched, so a
    # bad constructor argument can never reach the transport.
    my $lang = defined $arg{lang} ? $arg{lang} : 'en';
    _check_lang($lang);

    my $max_neighbors = exists $arg{max_neighbors} ? $arg{max_neighbors} : 25;
    _check_max_neighbors($max_neighbors);

    my $style = defined $arg{style} ? $arg{style} : 'path';
    _check_style($style);

    my $qtype = defined $arg{qtype} ? $arg{qtype} : 'entry';
    _check_identifier($qtype, 'qtype');

    my $idtype = defined $arg{idtype} ? $arg{idtype} : 'word';
    _check_identifier($idtype, 'idtype');

    my $self = bless {
        base_url      => defined $arg{base_url} ? $arg{base_url}
                       : defined $ENV{DICTIONARY_API_BASE} ? $ENV{DICTIONARY_API_BASE}
                       : 'https://api.dictionary.invalid/v1',
        lang          => $lang,
        style         => $style,
        qtype         => $qtype,
        idtype        => $idtype,
        fetcher       => $arg{fetcher},
        timeout       => defined $arg{timeout} ? $arg{timeout} : 10,
        max_neighbors => $max_neighbors,
        json          => $arg{json} || JSON::PP->new->utf8(0)->allow_nonref(1),
    }, $class;
    if (defined $self->{base_url} && !ref $self->{base_url}) {
        $self->{base_url} =~ s{/+\z}{};
    }
    return $self;
}

sub base_url { return $_[0]{base_url} }
sub lang     { return $_[0]{lang} }
sub style    { return $_[0]{style} }
sub qtype    { return $_[0]{qtype} }
sub idtype   { return $_[0]{idtype} }

# ---------------------------------------------------------- argument checks

sub _check_lang {
    my ($lang) = @_;
    return 1 if defined $lang && !ref $lang && $lang =~ $LANG_RE;
    die Dictionary::Error->new(
        kind    => 'usage',
        message => 'lang must be 1-8 ASCII letters with optional hyphen-separated '
                 . '1-8 character alphanumeric subtags, got ' . _shown($lang),
    );
}

sub _check_max_neighbors {
    my ($value) = @_;
    return 1 unless defined $value;
    my $text = ref $value ? undef : "$value";
    return 1 if defined $text && $text =~ /\A[0-9]+\z/;
    die Dictionary::Error->new(
        kind    => 'usage',
        message => 'max_neighbors must be a nonnegative integer or undef, got '
                 . _shown($value),
    );
}

sub _check_style {
    my ($style) = @_;
    return 1 if defined $style && !ref $style && $STYLE{$style};
    die Dictionary::Error->new(
        kind    => 'usage',
        message => 'style must be one of ' . join(', ', @STYLES) . ', got '
                 . _shown($style),
    );
}

sub _check_identifier {
    my ($value, $name) = @_;
    return 1 if defined $value && !ref $value && $value =~ $IDENT_RE;
    die Dictionary::Error->new(
        kind    => 'usage',
        message => "$name must be an ASCII identifier (a letter followed by up to "
                 . '31 letters, digits or underscores), got ' . _shown($value),
    );
}

# Render an offending value for an error message using printable ASCII only, so
# a newline or a wide character cannot break the one-line message.
sub _shown {
    my ($value) = @_;
    return 'undef' unless defined $value;
    return 'a ' . ref($value) . ' reference' if ref $value;
    my $text = "$value";
    $text =~ s/([^\x20-\x7e])/sprintf('\\x{%X}', ord $1)/ge;
    $text = substr($text, 0, 60) . '...' if length $text > 60;
    return "'$text'";
}

# ---------------------------------------------------------------- public API

sub lookup {
    my ($self, $word) = @_;
    my $raw = $self->_entries($word);
    return $self->normalize_entry($raw->[0]);
}

sub lookup_all {
    my ($self, $word) = @_;
    my $raw = $self->_entries($word);
    return [ map { $self->normalize_entry($_) } @$raw ];
}

sub neighbors {
    my ($self, $word) = @_;
    $self->_require_word($word);
    my $path = $self->_request_path('/neighbors', $word);
    my $data = $self->_get_json($path, "neighbors of '$word'");

    my @items = ref $data eq 'ARRAY' ? @$data : ();
    my $self_lc = lc $word;
    my (%seen, @out);
    for my $item (@items) {
        # A neighbor must be a word, i.e. a JSON string (bare or under "word").
        my $candidate = ref $item eq 'HASH' ? _str($item->{word}) : _string_item($item);
        next unless length $candidate;
        next if lc($candidate) eq $self_lc;
        next if $seen{ lc $candidate }++;
        push @out, $candidate;
    }

    my $max = $self->{max_neighbors};
    if (defined $max && $max >= 0 && @out > $max) {
        @out = @out[ 0 .. $max - 1 ];
    }
    return \@out;
}

sub normalize_entry {
    my ($self, $raw) = @_;
    $raw = {} unless ref $raw eq 'HASH';

    my $entry = {
        word     => _str($raw->{word}),
        phonetic => _str($raw->{phonetic}),
        origin   => _str($raw->{origin}),
        audio    => '',
        meanings => [],
    };

    if (ref $raw->{phonetics} eq 'ARRAY') {
        for my $ph (@{ $raw->{phonetics} }) {
            next unless ref $ph eq 'HASH';
            my $audio = _str($ph->{audio});
            if (length $audio) { $entry->{audio} = $audio; last }
        }
    }

    if (ref $raw->{meanings} eq 'ARRAY') {
        for my $meaning (@{ $raw->{meanings} }) {
            next unless ref $meaning eq 'HASH';
            my @definitions;
            if (ref $meaning->{definitions} eq 'ARRAY') {
                for my $def (@{ $meaning->{definitions} }) {
                    next unless ref $def eq 'HASH';
                    push @definitions, {
                        definition => _str($def->{definition}),
                        example    => _str($def->{example}),
                        synonyms   => _str_list($def->{synonyms}),
                        antonyms   => _str_list($def->{antonyms}),
                    };
                }
            }
            my $pos = defined $meaning->{partOfSpeech} ? $meaning->{partOfSpeech}
                    : $meaning->{part_of_speech};
            push @{ $entry->{meanings} }, {
                part_of_speech => _str($pos),
                definitions    => \@definitions,
                synonyms       => _str_list($meaning->{synonyms}),
                antonyms       => _str_list($meaning->{antonyms}),
            };
        }
    }

    return $entry;
}

# ---------------------------------------------------------------- internals

sub _entries {
    my ($self, $word) = @_;
    $self->_require_word($word);
    my $path = $self->_request_path('/entries', $word);
    my $data = $self->_get_json($path, "entry for '$word'");

    my @raw;
    if    (ref $data eq 'ARRAY') { @raw = @$data }
    elsif (ref $data eq 'HASH')  { @raw = ($data) }
    @raw = grep { ref $_ eq 'HASH' } @raw;

    unless (@raw) {
        die Dictionary::Error->new(
            kind    => 'not_found',
            message => "no entry found for '$word'",
        );
    }
    return \@raw;
}

# Build the request path for one resource.
#
# Path style is the default and has not changed: /entries/{lang}/{word}.
# Query style moves every value into the query string in a fixed order --
# qtype, idtype, id, lang -- and every value goes through the same uri_escape
# as a path segment, so an id containing & or = cannot inject a parameter.
sub _request_path {
    my ($self, $resource, $word) = @_;
    my $escaped = $self->uri_escape($word);

    return sprintf '%s/%s/%s', $resource, $self->{lang}, $escaped
        unless $self->{style} && $self->{style} eq 'query';

    return sprintf '%s?qtype=%s&idtype=%s&id=%s&lang=%s',
        $resource,
        $self->uri_escape($self->{qtype}),
        $self->uri_escape($self->{idtype}),
        $escaped,
        $self->uri_escape($self->{lang});
}

sub _require_word {
    my ($self, $word) = @_;
    unless (defined $word && length $word) {
        die Dictionary::Error->new(kind => 'usage', message => 'a word is required');
    }
    if ($word =~ /\A\s*\z/) {
        die Dictionary::Error->new(kind => 'usage', message => 'word may not be blank');
    }
    if ($word =~ m{[/\\\x00-\x1f]}) {
        die Dictionary::Error->new(
            kind    => 'usage',
            message => 'word may not contain slashes or control characters',
        );
    }
    return 1;
}

sub _get_json {
    my ($self, $path, $desc) = @_;
    my $url = $self->{base_url} . $path;
    my $res = $self->_fetch($url);
    my $status = $res->{status};

    if    ($status == 404) { die Dictionary::Error->new(kind => 'not_found',    status => 404,     message => "no $desc (HTTP 404)") }
    elsif ($status == 429) { die Dictionary::Error->new(kind => 'rate_limited', status => 429,     message => "rate limited asking for $desc") }
    elsif ($status >= 500) { die Dictionary::Error->new(kind => 'server',       status => $status, message => "upstream error asking for $desc") }
    elsif ($status < 200 || $status >= 300) {
        die Dictionary::Error->new(kind => 'http', status => $status, message => "unexpected HTTP $status asking for $desc");
    }

    my $text = $self->_decode_body($res);
    return $self->_decode_json($text, $url);
}

sub _decode_body {
    my ($self, $res) = @_;
    my $bytes = $res->{body};
    $bytes = '' unless defined $bytes;

    # An injected fetcher may hand us an already-decoded character string.
    my $text;
    if (utf8::is_utf8($bytes)) {
        $text = $bytes;
    }
    else {
        my $content_type = defined $res->{content_type} ? $res->{content_type} : '';
        my $charset = 'utf-8';
        if ($content_type =~ /charset\s*=\s*"?([^";\s]+)"?/i) {
            $charset = lc $1;
        }

        my $encoding = $CHARSET{$charset};
        unless (defined $encoding) {
            die Dictionary::Error->new(
                kind    => 'encoding',
                message => "unsupported charset '$charset' in response",
            );
        }

        $text = eval { Encode::decode($encoding, $bytes, Encode::FB_CROAK) };
        if (!defined $text) {
            my $why = $@;
            $why = 'malformed byte sequence' if !defined $why || !length $why;
            chomp $why;
            die Dictionary::Error->new(
                kind    => 'encoding',
                message => "response body is not valid $encoding: $why",
            );
        }
    }

    # A stray UTF-8 BOM is decoration, not payload: JSON itself has no BOM.
    $text =~ s/\A\x{feff}//;
    return $text;
}

sub _decode_json {
    my ($self, $text, $url) = @_;
    my $data = eval { $self->{json}->decode($text) };
    if ($@) {
        my $why = $@;
        $why = 'undecodable JSON' if !defined $why || !length $why;
        chomp $why;
        die Dictionary::Error->new(
            kind    => 'parse',
            message => "invalid JSON from $url: $why",
        );
    }
    return $data;
}

sub _fetch {
    my ($self, $url) = @_;
    my $fetcher = $self->{fetcher} ||= _http_fetcher($self->{timeout});

    my $raw = eval { $fetcher->($url) };
    if (!defined $raw) {
        my $why = $@ || 'fetcher returned nothing';
        die Dictionary::Error->new(kind => 'network', message => 'transport failure for ' . $url . ': ' . _clean($why));
    }
    unless (ref $raw eq 'HASH') {
        die Dictionary::Error->new(kind => 'network', message => "fetcher returned a non-hash response for $url");
    }
    if (my $transport = $raw->{transport_error}) {
        die Dictionary::Error->new(kind => 'network', message => 'transport failure for ' . $url . ': ' . _clean($transport));
    }

    return {
        status       => defined $raw->{status} ? $raw->{status} : 0,
        body         => defined $raw->{body}   ? $raw->{body}   : '',
        content_type => defined $raw->{content_type} ? $raw->{content_type} : '',
    };
}

# The ONLY network code in the project. Not exercised by the offline suite.
sub _http_fetcher {
    my ($timeout) = @_;
    require HTTP::Tiny;
    my $ua = HTTP::Tiny->new(
        timeout => $timeout,
        agent   => "dictionary-client/$VERSION",
    );
    return sub {
        my ($url) = @_;
        my $res = $ua->get($url);
        my $out = {
            status       => $res->{status},
            body         => defined $res->{content} ? $res->{content} : '',
            content_type => (($res->{headers} || {})->{'content-type'} || ''),
        };
        if (!$res->{success} && $res->{status} == 599) {
            $out->{transport_error} = defined $res->{content} ? $res->{content} : 'connection failed';
        }
        return $out;
    };
}

sub _clean {
    my ($thing) = @_;
    my $text = ref $thing ? "$thing" : (defined $thing ? $thing : '');
    $text =~ s/\s+\z//;
    $text =~ s/\s+/ /g;
    $text = substr($text, 0, 200) if length($text) > 200;
    return length($text) ? $text : 'unknown error';
}

sub _str {
    my ($value) = @_;
    return '' unless defined $value;
    return '' if ref $value;
    return "$value";
}

# Bare neighbor items must be JSON strings. Numbers and other non-strings are
# not words, so they are dropped instead of being stringified into "5".
sub _string_item {
    my ($value) = @_;
    return '' unless defined $value && !ref $value;
    return '' if _is_number($value);
    return "$value";
}

# True when the scalar is a JSON number (numeric slot only), false for strings
# such as "5" that arrived as JSON text.
sub _is_number {
    my ($value) = @_;
    return 0 if !defined $value || ref $value;
    require B;
    my $flags = B::svref_2object(\$value)->FLAGS;
    my $numeric = ($flags & B::SVp_IOK()) || ($flags & B::SVp_NOK());
    my $stringy = ($flags & B::SVp_POK());
    return ($numeric && !$stringy) ? 1 : 0;
}

sub _str_list {
    my ($value) = @_;
    return [] unless ref $value eq 'ARRAY';
    return [ map { "$_" } grep { defined && !ref } @$value ];
}

# Percent-encode a word as UTF-8 bytes; unreserved characters pass through.
#
# Contract: the argument is a word, normally a character string. A byte string
# that already contains valid UTF-8 bytes is encoded as-is; a byte string with
# stray high bytes is read as Latin-1 and encoded once, so nothing is ever
# double-encoded.
#
# Encode::decode() with a CHECK flag may modify the scalar it is handed, so it
# only ever sees a throwaway copy here. Handing it the caller's word used to
# make this function return '' for every plain byte string, because the word
# had already been consumed by the successful probe.
#
# Works as a method ($client->uri_escape($w)) or as a plain function
# (Dictionary::Client::uri_escape($w)).
sub uri_escape {
    my $word;
    if    (@_ >= 2) { $word = $_[1] }
    elsif (@_ == 1) { $word = $_[0] }
    return '' unless defined $word;

    my $work = "$word";    # private copy: $word is never touched again

    my $bytes;
    if (utf8::is_utf8($work)) {
        $bytes = Encode::encode('UTF-8', "$work");
    }
    else {
        # Byte string: keep the octets when they are already valid UTF-8,
        # otherwise lift Latin-1 characters into UTF-8 exactly once. Both the
        # probe and the fallback work on fresh copies of the word.
        my $probe = "$work";
        my $decoded = eval { Encode::decode('UTF-8', $probe, Encode::FB_CROAK) };
        if (defined $decoded) {
            $bytes = Encode::encode('UTF-8', "$decoded");
        }
        else {
            $bytes = Encode::encode('UTF-8', "$work");
        }
    }
    $bytes = "$work" unless defined $bytes;

    # Escape octet by octet using ord/substr on a byte string: nothing here
    # depends on character semantics or on regex encoding rules.
    my $out = '';
    my $length = length $bytes;
    for my $index (0 .. $length - 1) {
        my $code = ord substr($bytes, $index, 1);
        if (   ($code >= 0x30 && $code <= 0x39)                        # 0-9
            || ($code >= 0x41 && $code <= 0x5a)                        # A-Z
            || ($code >= 0x61 && $code <= 0x7a)                        # a-z
            || $code == 0x2d || $code == 0x2e                         # - .
            || $code == 0x5f || $code == 0x7e)                        # _ ~
        {
            $out .= chr $code;
        }
        else {
            $out .= sprintf '%%%02X', $code;
        }
    }
    return $out;
}

1;
