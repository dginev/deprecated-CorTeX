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

use File::Spec::Functions qw/catdir catfile/;
use File::Copy;
use File::Path qw/rmtree/;
use Data::Dumper;
use List::MoreUtils qw/uniq/;

use CorTeX::Backend;
use CorTeX::Util::Traverse;
use CorTeX::Util::DB_File_Utils qw(get_db_file_field set_db_file_field);
use CorTeX::Util::RDFWrappers qw(xsd);

sub new {
  my ($class,%opts) = @_;
  return unless $opts{root}; # Root is mandatory
  $opts{verbosity}=0 unless defined $opts{verbosity};
  $opts{upper_bound}=9999999999 unless $opts{upper_bound};
  $opts{organization} = 'canonical' unless $opts{organization};
  $opts{organization} = lc($opts{organization});
  my $log;
  set_db_file_field('pending-corpora',join(':',uniq($opts{root},split(':',get_db_file_field('pending-corpora')||''))));
  # Import a canonically organized directory subtree:
  my $walker = CorTeX::Util::Traverse->new(root=>$opts{root},verbosity=>$opts{verbosity});
  my $corpus_name = $walker->job_name;
  set_db_file_field("$opts{root}-name",$corpus_name);

  if ($opts{organization} eq 'arxiv.org') {
    set_db_file_field("$opts{root}-state",'Unpacking');
    # Bookkeeping counters:
    my ($tars_counter,$subdir_counter, $pdf_counter, $third_level_counter, $final_counter) = (0,0,0,0,0);

    # For the arXiv corpus, we need to unpack all .tar files in the root directory,
    # and then recursively unpack inwards.
    opendir(my $dh, $opts{root});
    my @top_level_entries = readdir($dh);
    closedir($dh);
    my @tars = sort grep {/\.tar$/ && (-f catfile($opts{root},$_))} @top_level_entries;
    my %already_extracted = map {($_=>1)}  grep {-d catdir($opts{root},$_)} @top_level_entries;
    my @new_tars = grep {/^arXiv_src_(\d+)\_/; !$already_extracted{$1};} @tars;
    $tars_counter = scalar(@new_tars);
    print STDERR "\nTars to unpack: ",join("\n",@new_tars),"\n" if $tars_counter;
    # First extract all top-level tars
    foreach my $file(@new_tars) { 
      my $untar = "tar -xf ".catfile($opts{root},$file)." -C $opts{root}";
      system($untar); }
    # Next, clean and unpack second-level directories
    my @subdirs = ();
    foreach my $file(@tars) {
      if ($file =~ /^arXiv_src_(\d+)_/) {
        push @subdirs, $1; }}
    foreach my $subdir_name(uniq(@subdirs)) { # Unique, since arXiv has multiple tar fragments per a month's directory   
      my $subdir_path = catdir($opts{root},$subdir_name);
      next unless -d $subdir_path; # Skip if not present
      $subdir_counter++;
      opendir(my $subh, $subdir_path);
      my @subdir_files = readdir($subh);
      closedir($subh);
      # Wipe away .pdf files      
      $pdf_counter = scalar(grep {/\.pdf$/} @subdir_files);
      if ($pdf_counter > 0) {
	  system("rm $subdir_path/*.pdf"); }
      # Extract .gz files and delete sources.
      $third_level_counter = scalar(grep {/\.gz$/} @subdir_files);
      if ($third_level_counter > 0) { # Only unzip dirs that still have .gz files in them
	  system("gunzip -r $subdir_path"); }
      # All extracted files that have no extensions need to be .tar
      # and need to be extracted again in a subdirectory
      opendir($subh, $subdir_path);
      @subdir_files = readdir($subh);
      closedir($subh);
      foreach my $implicit_tar_file(sort grep {/\d+$/} @subdir_files) {
        my $implicit_tar_path = catfile($subdir_path,$implicit_tar_file);
	next if -d $implicit_tar_path; # We skip already extracted dirs
	print STDERR "Unpacking: $implicit_tar_path\n";
        my $full_tar_path = catfile($subdir_path,$implicit_tar_file.'.tar');
        move($implicit_tar_path,$full_tar_path);
        mkdir($implicit_tar_path);
        # Unpack the tar into its 3rd level directory:
        if (!system("tar -tf $full_tar_path 2>\&1 >/dev/null")) { # A tar file
          system("tar xf $full_tar_path -C $implicit_tar_path");
          unlink($full_tar_path); }
        else { # Not a tar, then we have a single TeX file - move to its own directory
          move($full_tar_path,catfile($implicit_tar_path,$implicit_tar_file.'.tex')); }
        if (-d $implicit_tar_path) {
          my $main_tex_file = guessTeXFile($implicit_tar_path);
          if ($main_tex_file) {
            $final_counter++;
            move($main_tex_file, catfile($implicit_tar_path,$implicit_tar_file.'.tex')); }
          else {
            $log .= "Warning:TeX:missing Missing main TeX file for $implicit_tar_file\n";
            rmtree($implicit_tar_path); }
          # Check if we can find the main .tex file. If we can - rename it to the main directory.
        }
      }
    }  
    # Report on the arXiv unpacking:
    if ($tars_counter > $subdir_counter) {
      $log .= "Warning:extract:missing Tried to extract $tars_counter .tar files, created only $subdir_counter directories.\n"; }
    if ($pdf_counter) {
      $log .= "Warning:extract:discarded Discarded $pdf_counter PDF files.\n"; }
    if ($third_level_counter > $final_counter) { 
      $log .= "Warning:extract:discarded Out of $third_level_counter paper TARs, only $final_counter had a main TeX file.\n"; }
  }
  set_db_file_field("$opts{root}-state",'Traversing');
  # Start the traversal and import phase:
  my $checkpoint = get_db_file_field("$opts{root}-import-checkpoint");
  my $directory;
  #Fast-forward until checkpoint is reached:
  if ($checkpoint) {
    do {
      $directory = $walker->next_entry;
    } while (defined $directory && ($directory ne $checkpoint)); }
  my $backend = CorTeX::Backend->new(%opts);
  bless {walker=>$walker,verbosity=>$opts{verbosity},
        upper_bound=>$opts{upper_bound},
        backend=>$backend, processed_entries=>0,
        triple_queue=>[], log=>$log,
        corpus_name=>$corpus_name}, $class; }

sub set_directory {
  my ($self,$dir) = @_;
  if (defined $self->{walker}) {
    $self->{walker}->set_root($dir); }
  else {
    $self->{walker} = CorTeX::Util::Traverse->new(root=>$dir,verbosity=>$self->{verbosity});
  } }

sub process_next {
  my ($self) = @_;
  my $root = $self->{walker}->get_root;
  # 0. Check that we are within restrictions
  if ($self->{processed_entries} > $self->{upper_bound}) {
    $self->{log} .= "Upper bound reached!\n" if ($self->{verbosity}>0);
    set_db_file_field("$root-state",'Completed');
    set_db_file_field("$root-processed-entries",undef);
    set_db_file_field("$root-import-checkpoint",undef);
    set_db_file_field(join(':',uniq(grep {$_ ne $root} split(':',get_db_file_field('pending-corpora')))));
    return; }
  # 1. Fetch the next corpus entry to import
  my $directory = $self->{walker}->next_entry;
  if (! defined $directory) {
    $self->{log} .= "Traversal completed!\n" if ($self->{verbosity}>0);
    set_db_file_field("$root-state",'Completed');
    set_db_file_field("$root-processed-entries",undef);
    set_db_file_field("$root-import-checkpoint",undef);
    set_db_file_field(join(':',uniq(grep {$_ ne $root} split(':',get_db_file_field('pending-corpora')))));
    return; }
  # 1.1. Increase processed counter
  $self->{processed_entries}++;
  if (! ($self->{processed_entries} % 100)) {
    set_db_file_field("$root-import-checkpoint",$directory);
    set_db_file_field("$root-processed-entries",$self->{processed_entries}); }
  my $added = $self->backend->docdb->already_added($directory,$root);
  if (! $added) {
    #IMPORTANT TODO: Speed this up, make batch inserts once every 200 or so jobs, not this insert-per-job processing
    # 2. Import into eXist
    my $collection = $self->backend->docdb->insert_directory($directory,$self->{walker}->get_root);
    # 3. Add entry to SQL tasks, mark as queued for pre-processors:
    my $corpus_name = $self->{corpus_name};
    # Remove any traces of the task
    my $success_purge = $self->backend->taskdb->purge(corpus=>$corpus_name,entry=>$directory);
    $self->{log} .= "Error:Taskdb:purge Purge failed, bailing!\n" unless $success_purge;
    # Queue in the pre-processors
    print STDERR "Queueing $directory\n";
    my $success_queue = 
      $self->backend->taskdb->queue(corpus=>$corpus_name,entry=>$directory,service=>'import',status=>-1);
    $self->{log} .= "Error:Taskdb:queue Queue failed, bailing!\n".Dumper($self->backend->taskdb) unless $success_queue;
  }
  return 1;
}

sub process_all {
  my ($self) = @_;
  # TODO: Consider opening a transaction and keeping count,
  # so that we only commit e.g. on every 100 entries
  my $taskdb = $self->backend->taskdb;
  $taskdb->do($taskdb->{begin_transaction});
  while ($self->process_next) {}
  $taskdb->do('COMMIT'); }

sub get_processed_count {
  my ($self) = @_;
  $self->{processed_entries}; }

sub backend {
  my ($self) = @_;
  $self->{backend}; }

sub get_job_name {
  my ($self) = @_;
  $self->walker->job_name; }

sub guessTeXFile {
  my ($directory) = @_;
  opendir(my $dh, $directory);
  my @TeX_file_members = readdir($dh);
  closedir($dh);
  if (scalar(@TeX_file_members) == 1) {
    # One file, that's the input!
    return catfile($directory, $TeX_file_members[0]); }
  elsif (! scalar(@TeX_file_members)) { return; }
  # Heuristically determine the input (borrowed from arXiv::FileGuess)
  my %Main_TeX_likelihood;
  foreach my $tex_file (@TeX_file_members) {
    # Read in the content
    $tex_file = catfile($directory, $tex_file);
    # Open file and read first few bytes to do magic sequence identification
    # note that file will be auto-closed when $FILE_TO_GUESS goes out of scope
    open(my $FILE_TO_GUESS, '<', $tex_file) ||
      (print STDERR "failed to open '$tex_file' to guess its format: $!. Continuing.\n");
    local $/ = "\n";
    my ($maybe_tex, $maybe_tex_priority, $maybe_tex_priority2);
    TEX_FILE_TRAVERSAL:
    while (<$FILE_TO_GUESS>) {
      if ((/\%auto-ignore/ && $. <= 10) ||    # Ignore
        ($. <= 10 && /\\input texinfo/) ||    # TeXInfo
        ($. <= 10 && /\%auto-include/))       # Auto-include
      { $Main_TeX_likelihood{$tex_file} = 0; last TEX_FILE_TRAVERSAL; }    # Not primary
      if ($. <= 12 && /^\r?%\&([^\s\n]+)/) {
        if ($1 eq 'latex209' || $1 eq 'biglatex' || $1 eq 'latex' || $1 eq 'LaTeX') {
          $Main_TeX_likelihood{$tex_file} = 3; last TEX_FILE_TRAVERSAL; }    # LaTeX
        else {
          $Main_TeX_likelihood{$tex_file} = 1; last TEX_FILE_TRAVERSAL; } }    # Mac TeX
          # All subsequent checks have lines with '%' in them chopped.
          #  if we need to look for a % then do it earlier!
      s/\%[^\r]*//;
      if (/(?:^|\r)\s*\\document(?:style|class)/) {
        $Main_TeX_likelihood{$tex_file} = 3; last TEX_FILE_TRAVERSAL; }    # LaTeX
      if (/(?:^|\r)\s*(?:\\font|\\magnification|\\input|\\def|\\special|\\baselineskip|\\begin)/) {
        $maybe_tex = 1;
        if (/\\input\s+amstex/) {
          $Main_TeX_likelihood{$tex_file} = 2; last TEX_FILE_TRAVERSAL; } }    # TeX Priority
      if (/(?:^|\r)\s*\\(?:end|bye)(?:\s|$)/) {
        $maybe_tex_priority = 1; }
      if (/\\(?:end|bye)(?:\s|$)/) {
        $maybe_tex_priority2 = 1; }
      if (/\\input *(?:harv|lanl)mac/ || /\\input\s+phyzzx/) {
        $Main_TeX_likelihood{$tex_file} = 1; last TEX_FILE_TRAVERSAL; }        # Mac TeX
      if (/beginchar\(/) {
        $Main_TeX_likelihood{$tex_file} = 0; last TEX_FILE_TRAVERSAL; }        # MetaFont
      if (/(?:^|\r)\@(?:book|article|inbook|unpublished)\{/i) {
        $Main_TeX_likelihood{$tex_file} = 0; last TEX_FILE_TRAVERSAL; }        # BibTeX
      if (/^begin \d{1,4}\s+[^\s]+\r?$/) {
        if ($maybe_tex_priority) {
          $Main_TeX_likelihood{$tex_file} = 2; last TEX_FILE_TRAVERSAL; }      # TeX Priority
        if ($maybe_tex) {
          $Main_TeX_likelihood{$tex_file} = 1; last TEX_FILE_TRAVERSAL; }      # TeX
        $Main_TeX_likelihood{$tex_file} = 0; last TEX_FILE_TRAVERSAL; }        # UUEncoded or PC
      if (m/paper deliberately replaced by what little/) {
        $Main_TeX_likelihood{$tex_file} = 0; last TEX_FILE_TRAVERSAL; }
    }
    close $FILE_TO_GUESS || warn "couldn't close file: $!";
    if (!defined $Main_TeX_likelihood{$tex_file}) {
      if ($maybe_tex_priority) {
        $Main_TeX_likelihood{$tex_file} = 2; }
      elsif ($maybe_tex_priority2) {
        $Main_TeX_likelihood{$tex_file} = 1.5; }
      elsif ($maybe_tex) {
        $Main_TeX_likelihood{$tex_file} = 1; }
      else {
        $Main_TeX_likelihood{$tex_file} = 0; }
    }
  }
  # The highest likelihood (>0) file gets to be the main source.
  my @files_by_likelihood = sort { $Main_TeX_likelihood{$b} <=> $Main_TeX_likelihood{$a} } grep { $Main_TeX_likelihood{$_} > 0 } keys %Main_TeX_likelihood;
  if (@files_by_likelihood) {
   # If we have a tie for max score, grab the alphanumerically first file (to ensure deterministic runs)
    my $max_likelihood = $Main_TeX_likelihood{ $files_by_likelihood[0] };
    @files_by_likelihood = sort { $a cmp $b } grep { $Main_TeX_likelihood{$_} == $max_likelihood } @files_by_likelihood;
    return shift @files_by_likelihood; }
  return;
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
