#/usr/bin/perl -w
use strict;
use warnings;
use Mojo::UserAgent;
use Data::Dumper;

use lib '../lib';
use BuildSystem::Backend;
use XML::Simple;

my $backend = BuildSystem::Backend->new('sesame_url'=>'http://localhost:8080/openrdf-sesame',verbosity=>1);

my $repository = 'buildsys';
my $graph = 'meta';
my $s = 'exist:/db/ZBL-corpus/1/1/1226.62018/';

my $p = 'build:priority';
my $old = {
	   subject=>$s,
	   predicate=>$p,
	   object=>'"1"^^xsd:integer'
};
my $new = {
	   subject=>$s,
	   predicate=>$p,
	   object=>'"5"^^xsd:integer'
};

$backend->sesame->update_triple({new=>$new,old=>$old,graph=>$graph,repository=>$repository});
# my $xml_ref = $backend->sesame->sparql_query({graph=>$graph,repository=>$repository,
# 				     query=>'SELECT ?x WHERE { ?x build:priority "1"^^xsd:integer }'});


# my $results = [ map {$_->{binding}->{uri}} @{$xml_ref->{results}->{result}}];
# print STDERR "Response:\n",Dumper($results),"\n\n";
