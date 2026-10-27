package Dictionary::Error;
use strict;
use warnings;

use overload
    '""'     => sub { $_[0]->as_string },
    fallback => 1;

sub new {
    my ($class, %arg) = @_;
    my $self = {
        kind    => defined $arg{kind}    ? $arg{kind}    : 'unknown',
        message => defined $arg{message} ? $arg{message} : 'unspecified error',
        status  => $arg{status},
    };
    return bless $self, $class;
}

sub kind    { return $_[0]{kind} }
sub message { return $_[0]{message} }
sub status  { return $_[0]{status} }

sub as_string {
    my ($self) = @_;
    my $out = $self->{kind};
    $out .= ' (HTTP ' . $self->{status} . ')' if defined $self->{status};
    return $out . ': ' . $self->{message};
}

1;
