# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | eXist XML Database Backend Connector                                | #
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
  print STDERR " Annotation results: \n",Dumper(\@analysis_results);
  my $parsers = $db->{rdf_parsers};
  my $model = $db->model;
  $model->begin_bulk_ops;
  foreach my $result(@analysis_results) {
    my $data = $result->{annotations};
    next unless $data;
    my $rdf_format = $result->{formats}->[1];
    my $parser = $parsers->{$rdf_format};
    if (! defined $parser) {
       $parser = RDF::Trine::Parser->new( $rdf_format );
       $parsers->{$rdf_format} = $parser;
    }
    $parser->parse_into_model( $base_uri, $data, $model );
  }
  $model->end_bulk_ops;
}

1;

__END__