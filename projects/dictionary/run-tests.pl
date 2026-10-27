#!/usr/bin/perl
use strict;
use warnings;

# Offline runner: executes every t/*.t in a fresh perl and reports a verdict.
my @tests = sort glob 't/*.t';
unless (@tests) {
    print "no test files found\n";
    exit 1;
}

my $failed = 0;
for my $t (@tests) {
    print "# ----------------------------------------------------------------\n";
    print "# $t\n";
    my $rc = system($^X, '-Ilib', '-It/lib', $t);
    if ($rc != 0) {
        $failed++;
        print "not ok 1 - $t exited non-zero (status " . ($rc >> 8) . ")\n";
    }
}

if ($failed) {
    print "FAILED: $failed of " . scalar(@tests) . " test files failed\n";
    exit 1;
}
print "PASSED: all " . scalar(@tests) . " test files\n";
exit 0;
