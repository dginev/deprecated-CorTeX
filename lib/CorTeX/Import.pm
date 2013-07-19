# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | Corpus Import Module                                                | #
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

package CorTeX::Import;
use warnings;
use strict;

use File::Spec;

use CorTeX::Backend;
use CorTeX::Util::Traverse;
use CorTeX::Util::DB_File_Utils qw(get_db_file_field set_db_file_field);
use CorTeX::Util::RDFWrappers qw(xsd);

sub new {
  my ($class,%opts) = @_;
  $opts{verbosity}=0 unless defined $opts{verbosity};
  $opts{upper_bound}=9999999999 unless $opts{upper_bound};
  my $main_repos = $opts{main_repos} || 'buildsys';
  my $meta_graph = $opts{meta_graph} || 'meta';
  my $build_system_url = $opts{build_system_url} || 'http://lamapun.mathweb.org';

  my $walker = CorTeX::Util::Traverse->new(root=>$opts{root},verbosity=>$opts{verbosity})
    if $opts{root};
  my $corpus_name = $walker->job_name;
  my $job_url = $build_system_url.'/corpora/'.$corpus_name;

  my $backend = CorTeX::Backend->new(%opts);
  # Wipe away any existing collection if overwrite is enabled
  if ($opts{overwrite}) {
    $backend->taskdb->delete_corpus($corpus_name);
    $backend->taskdb->register_corpus($corpus_name);

    set_db_file_field('import_checkpoint',undef);
    $backend->docdb->delete_directory($opts{root},$opts{root});
    # Initialize a Build System repository in the triple store
    $backend->metadb->new_repository($main_repos,$opts{overwrite});
    # Register corpus name in triple store?
    $backend->metadb->add_triple({subject=>$job_url, predicate=>'rdfs:type', 
             object=>xsd("Corpus"),repository=>$main_repos,graph=>$meta_graph});
    $backend->metadb->add_triple({subject=>$job_url, predicate=>'build:entryType', 
             object=>xsd($opts{entry_setup}),repository=>$main_repos,graph=>$meta_graph})
    if defined $opts{entry_setup};
    # Delete corpus entries in the SQL database
  }

  my $checkpoint = get_db_file_field('import_checkpoint');
  my $directory;
  #Fast-forward until checkpoint is reached:
  if ($checkpoint) {
    do {
      $directory = $walker->next_entry;
    } while (defined $directory && ($directory ne $checkpoint));
  }

  bless {walker=>$walker,verbosity=>$opts{verbosity},
        upper_bound=>$opts{upper_bound},
	      backend=>$backend, job_url=>$job_url, processed_entries=>0,
	      main_repos=>$main_repos,meta_graph=>$meta_graph,
        entry_setup=>$opts{entry_setup},
        triple_queue=>[],
        corpus_name=>$corpus_name,
        build_system_url=>$build_system_url}, $class;
}

sub set_directory {
  my ($self,$dir) = @_;
  if (defined $self->{walker}) {
    $self->{walker}->set_root($dir);
  } else {
    $self->{walker} = CorTeX::Util::Traverse->new(root=>$dir,verbosity=>$self->{verbosity});
  }
}

sub process_next {
  my ($self) = @_;
  # 0. Check that we are within restrictions
  if ($self->{processed_entries} > $self->{upper_bound}) {
    print STDERR "Upper bound reached!\n" if ($self->{verbosity}>0);
    return;
  }
  # 1. Fetch the next corpus entry to import
  my $directory = $self->{walker}->next_entry;
  if (! defined $directory) {
    print STDERR "Traversal completed!\n" if ($self->{verbosity}>0);
    return;
  }
  #print STDERR "Entering processing mode for: $directory\n\n" if ($self->{verbosity}>0);
  # 1.1. Increase processed counter
  $self->{processed_entries}++;
  if (! ($self->{processed_entries} % 100)) {
    set_db_file_field('import_checkpoint',$directory);
    $self->backend->metadb->add_triples({triples=>$self->{triple_queue}, repository=>$self->{main_repos},graph=>$self->{meta_graph}});
    $self->{triple_queue} = []; # TODO: Check for add failure!!!
  }
  my $added = $self->backend->docdb->already_added($directory,$self->{walker}->get_root);
  if (! $added) {
    # 2. Import into eXist
    my $collection = $self->backend->docdb->insert_directory($directory,$self->{walker}->get_root);
    # OLD3. Mark priority as 1 in Sesame:
    #push @{$self->{triple_queue}}, {subject=>"exist:$collection",predicate=>'build:priority',object=>xsd(1)};
    # 3. Add entry to SQL tasks, mark as queued for pre-processors:
    my $corpus_name = $self->{corpus_name};
    # Remove any traces of the task
    my $success_purge = $self->backend->taskdb->purge(corpus=>$corpus_name,entry=>$directory);
    print STDERR "Purge failed, bailing!\n" unless $success_purge;
    # Queue in the pre-processors
    print STDERR "Queueing $directory\n";
    my $success_queue = 
      $self->backend->taskdb->queue(corpus=>$corpus_name,entry=>$directory,service=>'import',status=>-1);
    print STDERR "Queue failed, bailing!\n" unless $success_queue;
  }
  return 1;
}

sub process_all {
  my ($self) = @_;
  # TODO: Consider opening a transaction and keeping count,
  # so that we only commit e.g. on every 100 entries
  while ($self->process_next) {}
  set_db_file_field('import_checkpoint',undef);
}

sub get_processed_count {
  my ($self) = @_;
  $self->{processed_entries};
}

sub backend {
  my ($self) = @_;
  $self->{backend};
}

sub get_job_name {
  my ($self) = @_;
  $self->walker->job_name;
}

1;

__END__

=pod 

=head1 NAME

C<CorTeX::Import> - Driver for Corpus Imports

=head1 SYNOPSIS

    use CorTeX::Import;
    $importer=CorTeX::Import->new(root=>$directory, verbosity=>0|1,
                                       exist_url=>$URL, upper_bound=>$integer);
    $importer->set_directory($directory);
    $importer->process_next;
    $importer->process_all;
    my $count = $importer->get_processed_count;
    my $name = $importer->get_job_name;

=head1 DESCRIPTION

Main Import module for populating an eXist databse with corpus entries, accessed via
  the file system. The reason this module is separate from the Util::Traversal module
  is to enable easy future integration with other corpus APIs,
  such as arXiv's OAI downloads

The convention for a directory to be considered a corpus entry is for the directory
  and main TeX file to share a common base filename. For example:

mainname/
mainname/mainname.tex
mainname/other.tex
mainname/img
mainname/bib


=head2 METHODS

=over 4

=item C<< $importer=CorTeX::Import->new; >>

Create a new importer object. Supported options:
  - root=>$directory
  Path to the corpus top-level directory on the file system.
  The name of the directory will be assumed as the official corpus name.

  - verbosity=>0|1,
  Log verbosity, 0 for quiet, 1 for verbose 

  - exist_url=>$URL
  The eXist XML database URL for XML-RPC communication

  - sesame_url=>$URL
  The Sesame triple store URL for HTTP communication

  - upper_bound=>$integer
  Size limit on the imported corpus (useful for development, or sandbox creation)

=item C<< $importer->set_directory($directory); >>

Set a (new) root directory for the importer, resetting the current
  traversal status.

=item C<< $importer->process_next; >>

Traverse file system until next corpus entry is found and imported.
  Returns true if an entry has been successfully imported, false otherwise.

=item C<< $importer->process_all; >>

Processes all available entries, using process_next, or terminating when
  the 'upper_bound' is reached.

=item C<< my $count = $importer->get_processed_count; >>

Retrieve the count of the entries imported so far in the current traversal.

=item C<< my $name = $importer->get_job_name; >>

Retrieve the job/corpus name of the current traversal.
  (same as root directory name)

=back

=head1 AUTHOR

Deyan Ginev <d.ginev@jacobs-university.de>

=head1 COPYRIGHT

 Research software, produced as part of work done by 
 the KWARC group at Jacobs University Bremen.
 Released under the GNU Public License

=cut
