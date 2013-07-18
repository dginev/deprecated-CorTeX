# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | Backend Bridge Moduile                                              | #
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

package CorTeX::Backend::FileSystem;

use warnings;
use strict;
use File::Basename;
use feature qw(switch);
use Data::Dumper;

sub new {
  my ($class,%opts)=@_;
  $opts{inplace} = 1 unless defined $opts{inplace};
  return bless {%opts}, $class;
}

# Import API - empty if we use the corpus inplace
sub delete_directory {
  my ($self) = @_;
  return 1 if $self->{inplace};
}
sub already_added {
  my ($self) = @_;
  # For now readd every time
  # TODO: Conceptualize this better
  return 0 if $self->{inplace};
}
sub insert_directory {
  my ($self) = @_;
  return 1 if $self->{inplace};
}


1;