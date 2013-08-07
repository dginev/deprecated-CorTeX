# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | Initial Preprocessing from Tex to TEI-near XHTML                    | #
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
package CorTeX::Blueprint::tex_to_tei_xhtml_v0_1;
use warnings;
use strict;
use base qw(CorTeX::Blueprint);
use LaTeXML::Converter;
use LaTeXML::Util::Config;
use LLaMaPUn::LaTeXML;
use LLaMaPUn::Preprocessor::Purify;
use LLaMaPUn::Preprocessor::MarkTokens;

our $opts=LaTeXML::Util::Config->new(local=>1,whatsin=>'document',whatsout=>'document',
  format=>'dom',mathparse=>'no',timeout=>120,post=>0,
  defaultresources=>0);
$opts->check;

sub type {'conversion'}

sub convert {
  my ($self,%options) = @_;
  # I. Convert to XML
  my $source = "literal:".$options{workload};
  my $converter = LaTeXML::Converter->get_converter($opts);
  $converter->prepare_session($opts);
  my $response = $converter->convert($source);
  my ($latexml_dom, $status, $log) = map { $response->{$_} } qw(result status_code log) if defined $response;

  # Purify
  my $purified_dom = LLaMaPUn::Preprocessor::Purify::purify_noparse($latexml_dom,verbose=>0);
  # Tokenize
  my $marktokens = LLaMaPUn::Preprocessor::MarkTokens->new(document=>$purified_dom,verbose=>0);
  my $tokenized_dom = $marktokens->process_document;
  # Move to TEI HTML
  # print STDERR $tokenized_dom->toString(1),"\n\n";
  my $html_dom = xml_to_TEI_xhtml($tokenized_dom);

  my $result={};
  $result->{document}=$html_dom->toString(1);
  $result->{status}= -$status -1; # Adapt to the CorTeX scheme
  $result->{log} = $log;

  return $result; }

1;