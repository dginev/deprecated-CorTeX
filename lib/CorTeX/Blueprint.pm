# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | Blueprint template for CorTeX servies                               | #
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
package CorTeX::Blueprint;
use feature 'switch';

# Analysis, Converter and Aggregator services

sub process {
	my ($self,%options)=@_;	
	given (lc(type())) {
		when 'Map' {$self->map(%options)}
		when 'Reduce' {$self->map(%options)}
		when 'Convert' {$self->map(%options)}
		default {return;}
	}
}

1;