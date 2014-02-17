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
use Encode;

use File::Slurp;
use File::Path qw(make_path remove_tree);
use File::Spec;
use IO::String;
use Archive::Zip qw(:CONSTANTS :ERROR_CODES);
use XML::LibXML;
use XML::LibXML::XPathContext;

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
    my $entry_dir = $result->{entry};
    $entry_dir =~ /\/([^\/]+)$/;
    my $result_dir = File::Spec->catdir($entry_dir,'_cortex_'.$result->{service});
    make_path($result_dir);
    # Conversion results - add a new document
    if (! ref $document) { # Document is returned as a string 
      my $entry_name = $1 . "." . lc($result->{description}->{outputformat});
      my $result_file = File::Spec->catfile($result_dir,$entry_name);
      open my $fh, ">", $result_file;
      print $fh $document;
      close $fh; }
    else { # Document is returned as an Archive::Zip object
      foreach my $member($document->memberNames()) {
        $document->extractMember($member, File::Spec->catfile($result_dir,$member)); } }
  }

  foreach my $result(@aggregation_results) {
    # TODO: Aggregation results - add a new resource
  }
}

sub fetch_entry {
  my ($self,%options) = @_;
  my $entry = $options{entry};
  $entry =~ /\/([^\/]+)$/;
  my $name = $1;
  my $converter = $options{inputconverter};
  my $inputformat = $options{inputformat};
  $converter = '' if (!$converter || ($converter =~ /^import_v/));
  $converter = "_cortex_$converter" if $converter;
  my $directory = File::Spec->catdir($entry,$converter);
  # We have a simple (1 file) and a complex (1 archive) case:
  if ($options{'entry-setup'}) {
    $self->fetch_entry_complex($directory); }
 else {
    my $path = File::Spec->catfile($directory,"$name.$inputformat");
    $self->fetch_entry_simple($path,\%options); }}

sub fetch_entry_simple {
  my ($self,$path,$options) = @_;
  # Slurp the file and return:  
  if (-f $path ) {
    my $text = read_file( $path ) ;
    my $xpath = $options->{xpath};
    if ($text && $xpath && ($xpath ne '/')) {
      # We're asked for an XPath fragment, evaluate:
      my $parser = XML::LibXML->new();
      $parser->recover(1);
      $parser->expand_entities(0);
      $parser->load_ext_dtd(0);
      my $doc = $parser->parse_string($text);
      my $xc = XML::LibXML::XPathContext->new($doc->documentElement);
      $xc->registerNs('xhtml', 'http://www.w3.org/1999/xhtml');
      my ($node) = $xc->findnodes($xpath);
      $text = $node ? $node->toString(1) : ''; }
    return decode('UTF-8',$text); }
  else { return ; } }

sub fetch_entry_complex {
  my ($self,$directory) = @_;
  # Zip (just store really) and send everything in the directory, excluding subdirs starting with _cortex_
  my $archive = Archive::Zip->new();
  $archive->addTree($directory, undef, sub { (!/^_cortex_/) && (!/\.(?:zip|gz|epub|mobi|~)$/) }, COMPRESSION_STORED); 
  my $payload='';
  my $content_handle = IO::String->new($payload);
  undef $payload unless ($archive->writeToFileHandle($content_handle) == AZ_OK);
  return $payload; }

sub entry_to_url {
  return "file://".$_[1]; }

1;