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

sub new {
	my ($class, %options) = @_;
	bless {%options}, $class; }

sub process {
	my ($self,%options)=@_;	
	given (lc($self->type())) {
		when ('analysis') {$self->analyze(%options)}
		when ('aggregation') {$self->aggregate(%options)}
		when ('conversion') {$self->convert(%options)}
		default {return;}
	}}

# Blueprint API
sub type {return;}
sub convert {return;}
sub map {return;}
sub aggregate {return;}

1;