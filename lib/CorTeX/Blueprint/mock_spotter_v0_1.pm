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
<foaf:Person rdf:about="#danbri" xmlns:foaf="http://xmlns.com/foaf/0.1/">
  <foaf:name>Dan Brickley</foaf:name>
  <foaf:homepage rdf:resource="http://danbri.org/" />
  <foaf:openid rdf:resource="http://danbri.org/" />
  <foaf:img rdf:resource="/images/me.jpg" />
</foaf:Person>
EOL
  my $status = -4; # TODO
  my $log = "Fatal:mock:todo Needs to be implemented.";
  $result->{status}= $status; # Adapt to the CorTeX scheme
  $result->{log} = $log;  
  print STDERR "\n\nMock Spotter:\n";
  print STDERR Dumper($result);
  return $result; }

1;