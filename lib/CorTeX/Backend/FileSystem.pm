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
  return bless {%opts}, $class;
}

1;