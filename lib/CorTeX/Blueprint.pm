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
  my $response = {};
  local $@ = undef;
  my $eval_return = eval {
    given (lc($self->type())) {
      when ('analysis') {$response = $self->analyze(%options)}
      when ('aggregation') {$response = $self->aggregate(%options)}
      when ('conversion') {$response = $self->convert(%options)}
      default {}
    };
    1;};
  if (!$eval_return || $@) {
    $response = {
      status=>-4,
      log=>"Fatal:Blueprint:process $@"
    };}
  return $response; }

# Blueprint API
sub type {return;}
sub convert {return;}
sub map {return;}
sub aggregate {return;}

1;