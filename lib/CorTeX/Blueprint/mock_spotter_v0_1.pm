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
use base qw(CorTeX::Blueprint);

sub type {'analysis'}

sub analyze {
  my ($self,%options) = @_;
  my $document = $options{workload};

  # Spot single-word sentences: 
  my $result={};
  $result->{annotations}=<<'EOL';
<a1> <b1> <c1> .
@base <http://example.org/ns/> .
# In-scope base URI is http://example.org/ns/ at this point
<a2> <http://example.org/ns/b2> <c2> .
@base <foo/> .
# In-scope base URI is http://example.org/ns/foo/ at this point
<a3> <b3> <c3> .
@prefix : <bar#> .
:a4 :b4 :c4 .
@prefix : <http://example.org/ns2#> .
:a5 :b5 :c5 .
EOL
  my $status = -4; # TODO
  my $log = "Fatal:mock:todo Needs to be implemented.";
  $result->{status}= $status; # Adapt to the CorTeX scheme
  $result->{log} = $log;  
  return $result; }

1;