#!/usr/bin/perl -w
use strict;
use warnings;

# Note: you need s3cmd properly setup on your machine first!
my $available = ` s3cmd ls --add-header="x-amz-request-payer: requester" s3://arxiv/src/`;
my @available_tars = grep {defined} map {/(s3\:.+\.tar$)/; $1;} split("\n",$available);

# Obtain already downloaded URLs:
opendir my $cdir, '.';
my %downloaded_tars = map {("s3://arxiv/src/$_" => 1)} grep {/\.tar$/} readdir($cdir);
closedir $cdir;

my @new_tars = grep {!$downloaded_tars{$_};} @available_tars;

foreach my $new_tar(sort @new_tars) {
  print "Fetching: $new_tar\n";
  `s3cmd get --add-header="x-amz-request-payer: requester" $new_tar`; }
