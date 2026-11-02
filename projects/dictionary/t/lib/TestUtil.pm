package TestUtil;
use strict;
use warnings;

use Exporter 'import';
use File::Basename qw(dirname);
use File::Spec ();
use Encode ();

our @EXPORT = qw(fixture_bytes fixture_text recorded_fetcher);

sub _fixture_dir {
    return File::Spec->catdir(dirname(__FILE__), File::Spec->updir, 'fixtures');
}

sub fixture_bytes {
    my ($name) = @_;
    my $path = File::Spec->catfile(_fixture_dir(), $name);
    open my $fh, '<:raw', $path or die "open $path: $!";
    local $/;
    my $bytes = <$fh>;
    close $fh;
    return $bytes;
}

sub fixture_text {
    my ($name) = @_;
    return Encode::decode('UTF-8', fixture_bytes($name));
}

# Build an injected fetcher from a list of canned responses (hashrefs or coderefs).
# Returns (coderef, arrayref of requested URLs).
sub recorded_fetcher {
    my @responses = @_;
    my @seen;
    my $fetcher = sub {
        my ($url) = @_;
        push @seen, $url;
        die "unexpected request #" . scalar(@seen) . ": $url\n" unless @responses;
        my $next = shift @responses;
        return ref $next eq 'CODE' ? $next->($url) : $next;
    };
    return ($fetcher, \@seen);
}

1;
