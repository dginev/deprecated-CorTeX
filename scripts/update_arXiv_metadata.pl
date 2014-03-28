#!/usr/bin/perl -w
use strict;
use warnings;
use HTTP::OAI;
use JSON::XS qw(encode_json);

my @arxiv_metadata = ();
my %mathy_ids;
 
my $h = new HTTP::OAI::Harvester(baseURL=>'http://export.arXiv.org/oai2');
my $response = $h->repository($h->Identify);
if( $response->is_error ) {
        print "Error requesting Identify:\n",
                $response->code . " " . $response->message, "\n";
        exit;
}

my @sets = ();
# my $ls = $h->ListSets();
# while(my $set = $ls->next) {
#   print STDERR "Set : ",$set->setSpec,"\n";
#  push @sets, $set->setSpec; }

# Note: repositoryVersion will always be 2.0, $r->version returns
# the actual version the repository is running
print "Repository supports protocol version ", $response->version, "\n";
 
# Version 1.x repositories don't support metadataPrefix,
# but OAI-PERL will drop the prefix automatically
# if an Identify was requested first (as above)
# my $from = '1991-01-01';
# my $until = '2014-01-01';

# Using a handler
@sets=('math','cs','physics:math-ph','stat','physics:hep-th','physics:nlin');
foreach my $set(@sets) {
  print STDERR "ListIdentifiers for $set\n";
  my @set_ids = ();
  $response = $h->ListIdentifiers(
          metadataPrefix=>'oai_dc',
          set => $set,
          handlers=>{metadata=>'HTTP::OAI::Metadata::OAI_DC'}, );
  my $count = 0;
  while( my $rec = $response->next ) {
    $count++;
    if( $rec->is_error ) {
      print STDERR "Error: ",$response->message,"\n";
      next; }
    push @set_ids, $rec->identifier }
  @set_ids = map {s/^oai:arXiv.org://; $_;} @set_ids;
  foreach my $identifier (@set_ids) {
    $mathy_ids{$identifier} = 1; }
  print STDERR "Received $count records for set $set\n";
}

print STDERR "Total unique records: ",scalar(keys %mathy_ids),"\n";
open my $fh, ">", "extra_ids.txt";

print $fh join("\n",(sort keys %mathy_ids));
close $fh;
print STDERR "\n All done!\n";
1;