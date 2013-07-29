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

sub type {'conversion'}

sub convert {
my ($self,%options) = @_;
	my $result = {};

	print STDERR "Convert tex_to_tex_xhtml executed!\n";
	
	$result->{document}="something";
	$result->{status}=-4; # OK
	$result->{log} = "Fatal:mockup:generic We want a generic Fatal here.";

	return $result;
}

1;