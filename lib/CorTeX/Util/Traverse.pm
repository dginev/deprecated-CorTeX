# /=====================================================================\ #
# |  CorTeX Framework Utilities                                         | #
# | File System Traversal Module                                        | #
# |=====================================================================| #
# | Part of the MathSearch project: http://trac.kwarc.info/lamapun      | #
# |  Research software, produced as part of work done by:               | #
# |  the KWARC group at Jacobs University,                              | #
# | Copyright (c) 2012                                                  | #
# | Released under the GNU Public License                               | #
# |---------------------------------------------------------------------| #
# | Deyan Ginev <d.ginev@jacobs-university.de>                  #_#     | #
# | http://kwarc.info/people/dginev                            (o o)    | #
# \=========================================================ooo==U==ooo=/ #

package CorTeX::Util::Traverse;
use warnings;
use strict;

sub new {
  my ($class,%opts) = @_;
  $opts{root} = $opts{root}||'.';
  $opts{root} =~ s/\/+$//; # No trailing slashes
  $opts{verbosity} = 0 unless defined $opts{verbosity};
  bless {%opts,dirs=>[$opts{root}]}, $class;
}

sub set_root {
  my ($self,$root) = @_;
  $root =~ s/\/+$//; # No trailing slashes
  $self->{root} = $root;
  $self->{dirs} = [$root];
}
sub get_root {
  my ($self) = @_;
  $self->{root};
}

sub next_entry {
  my ($self) = @_;
  my ($entry,$found) = $self->step;
  ($entry,$found) = $self->step while ($entry && (!$found));
  return $entry;
}

sub step {
  my ($self) = @_;
  my $d = shift @{$self->{dirs}};
  return (undef,0) unless $d;
  # 1. Read in directory contents
  print STDERR "Examining $d...\n" if ($self->{verbosity}>0);
  opendir(my $dh ,$d) || die "can't opendir $d: $!";
  my @contents = sort readdir($dh);
  closedir $dh;

  #2. Check if main/main.tex setup is in place:
  $d =~/\/([^\/]+)$/;
  my $base = $1||'';
  if ((-d $d) && (-f "$d/$base.tex")) {
    #2.1. Found a leaf directory. code 1:
    return ($d,1);
  } else {
    #2.2. Still midway, traverse deeper. code 0:
    my @subds = map {"$d/$_"} grep {(!/^\./) && -d "$d/$_" } @contents;
    unshift @{$self->{dirs}}, @subds;
    return ($d,0);
  }
}

sub find_all {
  my ($self) = @_;
  my @all;
  while (my $entry = $self->next_entry) {
    push @all, $entry;
  }
  @all;
}

sub job_name {
  my ($self) = @_;
  $self->{root} =~ /\/([^\/]+)(\/?)$/;
  $1;
}

1;

__END__

=pod 

=head1 NAME

C<CorTeX::Util::Traverse> - File System Traversal for Retrieving Corpus Entries

=head1 SYNOPSIS

    use CorTeX::Util::Traverse;
    $walker=CorTeX::Util::Traverse->new(root=>$rootdir,verbosity=>0|1);
    $walker->set_root($rootdir);
    my $root = $walker->get_root;
    my $entry = $walker->next_entry;
    my ($directory,$entry_code) = $walker->step;
    my @all_entries = $walker->find_all;

=head1 DESCRIPTION

Utility module for traversing a file system tree and discovering corpus entries.
  The convention for a directory to be considered a corpus entry is for the directory
  and main TeX file to share a common base filename. For example:

mainname/
mainname/mainname.tex
mainname/other.tex
mainname/img
mainname/bib

=head2 METHODS

=over 4

=item C<< $walker=CorTeX::Util::Traverse->new(root=>$rootdir,verbosity=>0|1); >>

Creates a new traversal object capable of walking a directory tree, identified by the "root" key.
  Note that the root directory can also be specified via set_root.
  Verbosity is quiet by default, but can be turned on to print reports of the traversal progress.

=item C<< $walker->set_root($rootdir); >>

Sets the root directory for a file system traversal. Also resets any current traversal progress
  to a fresh start.

=item C<< $walker->get_root; >>

Retrieve the root directory of the current traversal.

=item C<< my ($directory,$entry_code) = $walker->step; >>

Steps through a single directory under the root in alphanumeric order.
  This method essentially performs depth-first search, updating the traversal state each step.

=item C<< my $entry = $walker->next_entry; >>

Steps through the file system until it finds the next corpus entry, or crawls the entire root tree.
  Incrementally keeps track of its traversal progress, as provided by the "step" method.

=item C<< my @all_entries = $walker->find_all; >>

Performs a full traversal of a previously specified directory root returning a list of corpus entries.

NOTE: Avoid this method for large corpora, in order to optimize memory consumption. Use the iterative
  next_entry instead. find_all is suitable for small document collections.

=back

=head1 AUTHOR

Deyan Ginev <d.ginev@jacobs-university.de>

=head1 COPYRIGHT

 Research software, produced as part of work done by 
 the KWARC group at Jacobs University Bremen.
 Released under the GNU Public License

=cut
