# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | MetaDB API for SQL Backends                                         | #
# |=====================================================================| #
# | Part of the LaMaPUn project: https://trac.kwarc.info/lamapun/       | #
# |  Research software, produced as part of work done by:               | #
# |  the KWARC group at Jacobs University                               | #
# | Copyright (c) 2012                                                  | #
# | Released under the GNU Public License                               | #
# |---------------------------------------------------------------------| #
# | Deyan Ginev <d.ginev@jacobs-university.de>                  #_#     | #
# | http://kwarc.info/people/dginev                            (o o)    | #
# \=========================================================ooo==U==ooo=/ #
package CorTeX::Backend::SQLMetaAPI;
use strict;
use warnings;
use Data::Dumper;
use Scalar::Util qw(blessed);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(new_repository add_triple complete_annotations model);

our $base_uri = 'http://cortex.kwarc.info';
use RDF::Trine::Parser;
use RDF::Trine::Store::DBI;
#use RDF::Tine::Model;

# $store = RDF::Trine::Store::DBI->new( $modelname, $dbh );
# my $model = RDF::Trine::Model->new($store);
# print $model->size . " RDF statements in store\n";

sub new_repository { }

sub add_triple { }

sub model {
  my ($db) = @_;
  my $model = $db->{model};
  if (! blessed($model)) {
    my $store = RDF::Trine::Store::DBI->new( "CorTeX", $db->safe );
    $model = RDF::Trine::Model->new($store);
    $db->{model} = $model;
  }
  return $model; }

sub complete_annotations {
  my ($db,$results) = @_;
  my @analysis_results = grep {defined $_->{annotations}} @$results;
  return unless @analysis_results;
  my $graph; # TODO : Delete this, the graph declaration should be inside the loop
  my $parsers = $db->{rdf_parsers};
  my $model = $db->model;
  $model->begin_bulk_ops;
  foreach my $result(@analysis_results) {
    my $data = $result->{annotations};
    next unless $data;
    my $rdf_format = $result->{formats}->[1];
    # Grab an RDF graph from our model
    $graph = $model->dataset_model(default=>[$result->{service}]);
    my $parser = $parsers->{$rdf_format};
    if (! defined $parser) {
       $parser = RDF::Trine::Parser->new( $rdf_format );
       $parsers->{$rdf_format} = $parser;
    }
    # What's in this graph currently ? We want to replace all annotations for this entry
    # print STDERR "Initial graph size: ",$graph->size,"\n\n";
    # open OUT, ">", "/tmp/graph.txt";
    # print OUT Dumper($graph->as_hashref);
    # close OUT;
    $parser->parse_into_model( $base_uri, $data, $graph );
  }
  $model->end_bulk_ops;
  # print STDERR "After complete, graph size: ",$graph->size,"\n\n";
}

1;

__END__