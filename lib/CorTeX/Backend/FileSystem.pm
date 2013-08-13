# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | DocDB API for using the File System                                 | #
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
use File::Path qw(make_path remove_tree);
use File::Spec;
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
  my ($self,@files) = @_;
  return 1;
}

sub complete_documents {
  my ($self,$results) = @_;
  return unless @$results;
  my @conversion_results = grep {$_->{document}} @$results;
  my @aggregation_results = grep {$_->{resource}} @$results;
  foreach my $result(@conversion_results) {
    #print STDERR Dumper($result);
    my $document = $result->{document};
    # Conversion results - add a new document
    my $entry_dir = $result->{entry};
    $entry_dir =~ /\/([^\/]+)$/;
    my $entry_name = $1 . "." . lc($result->{formats}->[1]);
    my $result_dir = File::Spec->catdir($entry_dir,$result->{service});
    my $result_file = File::Spec->catfile($result_dir,$entry_name);

    make_path($result_dir);
    open my $fh, ">", $result_file;
    print $fh $document;
    close $fh;
  }

  foreach my $result(@aggregation_results) {
    # Aggregation results - add a new resource
  }
}

sub fetch_entry {
  my ($self,%options) = @_;
  my $entry = $options{entry};
  $entry =~ /\/([^\/]+)$/;
  my $name = $1;
  my $converter = $options{inputconverter};
  my $inputformat = $options{inputformat};
  $converter = '' if ($converter =~ /^import_v/);
  $converter .= '/' if $converter;
  my $path = "$entry/$converter$name.$inputformat";
  # Slurp the file and return:  
  if (-f $path ) {
    my $text = read_file( $path ) ;
    return $text; }
  else { return ; } }

sub entry_to_url {
  return "file://".$_[1];
}

1;