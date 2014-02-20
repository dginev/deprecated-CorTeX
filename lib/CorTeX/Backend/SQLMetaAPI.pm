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
our @EXPORT = qw(new_repository add_triple complete_annotations model graph_report);

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
  my @analysis_results = grep {my $anno = $_->{annotations}; defined $anno && (ref $anno) && (scalar(@$anno)); } @$results;
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
    my $parser = $parsers->{$rdf_format};
    if (! defined $parser) {
       $parser = RDF::Trine::Parser->new( $rdf_format );
       $parsers->{$rdf_format} = $parser;
    }
    # First delete all existing annotations in the context/entry pair
    my $context = RDF::Trine::Node::Resource->new($result->{service});
    my $entry_subject = RDF::Trine::Node::Resource->new("file://".$result->{entry});
    $model->remove_statements($entry_subject,undef,undef,$context);
    # Then parse in the new annotations
    $parser->parse_into_model( $base_uri, $data, $model, (context=>$context));
  }
  $model->end_bulk_ops;
  ## Old Debug prints:
#   my $iterator = $model->get_contexts;
#   open OUT, ">", "/tmp/model.txt";
#   while (my $row = $iterator->next) {
#     print OUT Dumper($row);
#     my $statements = $model->get_statements(undef,undef,undef,$row);
#     while (my $st = $statements->next) {
#      print OUT $st->as_string,"\n"; }
#     print OUT "\n----------------------\n---------------\n";
#   }
#   close OUT;
}

sub graph_report {
  my ($db,%options) = @_;
  my ($entry, $service, $format) = map {$options{$_}} qw/entry service format/;
  my $model = $db->model;
  my $context = RDF::Trine::Node::Resource->new($service);
  my $entry_subject = RDF::Trine::Node::Resource->new("file://".$entry);
  my $statements = $model->get_statements($entry_subject,undef,undef,$context);
  my $report = [];
  while (my $st = $statements->next) {
    my ($s,$p,$o) = map {$_->as_string} $st->nodes;
    push @$report, "$s $p $o";
  }
  return $report; }

1;

__END__