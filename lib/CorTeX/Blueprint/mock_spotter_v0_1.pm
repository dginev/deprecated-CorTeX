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
package CorTeX::Blueprint::mock_spotter_v0_1;
use warnings;
use strict;
use Data::Dumper;
use base qw(CorTeX::Blueprint);

sub type {'analysis'}

sub analyze {
  my ($self,%options) = @_;
  my $document = $options{workload};

  # Spot single-word sentences: 
  my $result={};
  $result->{annotations}=<<'EOL';
<rdf:RDF
  xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
  xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#"
  xmlns:foaf="http://xmlns.com/foaf/0.1/">

  <foaf:Person rdf:about="#danbri" xmlns:foaf="http://xmlns.com/foaf/0.1/">
    <foaf:name>Dan Brickley</foaf:name>
    <foaf:homepage rdf:resource="http://danbri.org/" />
    <foaf:openid rdf:resource="http://danbri.org/" />
    <foaf:img rdf:resource="/images/me.jpg" />
  </foaf:Person>
</rdf:RDF>
EOL
  my $status = -4; # TODO
  my $log = "Fatal:mock:todo Needs to be implemented.";
  $result->{status}= $status; # Adapt to the CorTeX scheme
  $result->{log} = $log;  
  return $result; }

1;