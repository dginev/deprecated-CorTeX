#/usr/bin/perl -w
use strict;
use warnings;
use File::Copy;

# Cleans up a directory tree from LaTeXML or arXiv artefacts.

my $top_directory = shift||'.';
$top_directory =~ s/\/+$//; # No trailing slashes

descend($top_directory);

sub descend {
  my ($path) = @_;
  print STDERR "Visiting $path...\n";
  opendir (my $dir_handle,$path) or die " Can't read directory!\n $@\n";
  my @all_resources = map {$path.'/'.$_} grep { $_ !~ /^(\.)+$/} sort readdir($dir_handle);
  closedir $dir_handle;

  my @subdirs = grep {-d $_} @all_resources;
  my @files_to_erase = grep { /Makefile|(\.(pdf|xml|xhtml|html|css|log|cache))|(x(\d+)\.png)$/ } grep { -f $_ } @all_resources;
  unlink $_ foreach @files_to_erase;

  my @abs_to_move = map {/^(.+)\.abs$/; [$_,$1]; } grep {/^(.+)\.abs$/ && (-d $1) } grep {-f $_ } @all_resources;
  move($_->[0],$_->[1]."/") foreach @abs_to_move;
  descend($_) foreach @subdirs;
}
