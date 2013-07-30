# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | Initial Preprocessing from ZBL Tex to HTML5                         | #
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
package CorTeX::Blueprint::zbl_to_html_v0_1;
use warnings;
use strict;
use base qw(CorTeX::Blueprint);
use LaTeXML::Converter;
use LaTeXML::Util::Config;

our $opts=LaTeXML::Util::Config->new(local=>1,timeout=>120,profile=>'zbl');
$opts->check;

sub type {'conversion'}

sub convert {
  my ($self,%options) = @_;
  my $source = "literal:".$options{workload};
  my $converter = LaTeXML::Converter->get_converter($opts);
  $converter->prepare_session($opts);
  my $response = $converter->convert($source);
  my ($document, $status, $log) = map { $response->{$_} } qw(result status_code log) if defined $response;

  my $result={};
  $result->{document}=$document;
  $result->{status}= -$status -1; # Adapt to the CorTeX scheme
  $result->{log} = $log;

  return $result; }


1;