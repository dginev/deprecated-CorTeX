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

use File::Slurp;
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

sub insert_files {
  my (@files) = @_;
  return 1;
}

sub fetch_entry {
  my ($self,%options) = @_;
  my $entry = $options{entry};
  $entry =~ /\/([^\/]+)$/;
  my $name = "/$1.tex";
  $entry .= $name;
  # Slurp the file and return:  
  if (-f $entry ) {
    my $text = read_file( $entry ) ;
    return $text; }
  else { return ; } }

1;