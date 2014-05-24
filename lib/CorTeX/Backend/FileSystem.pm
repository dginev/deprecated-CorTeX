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

use Cwd;
use File::Slurp;
use File::Path qw(make_path remove_tree);
use File::Spec;
use JSON::XS qw(decode_json encode_json);
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
  if ($options{'entry-setup'} && (! $options{raw})) {
    $self->fetch_entry_complex($directory,\%options); }
 else {
    my $path = File::Spec->catfile($directory,"$name.$inputformat");
    $self->fetch_entry_simple($path,\%options); } }

sub fetch_entry_simple {
  my ($self,$path,$options) = @_;
  # Slurp the file and return:  
  if (-f $path ) {
    my $text = read_file( $path ) ;
    $text = decode('UTF-8',$text) if $path=~/\.(xml|x?html)$/; # Assume all our XML files are unicode
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
    return $options->{raw} ? $text : 
      JSON->new->utf8(1)->encode({document=>$text}); }
  else { return $options->{raw} ? '' : encode_json({}); } }

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

# Hacky, but needs to circumvent the undef issues
our $cwd_on_load = cwd();
sub Archive::Zip::Archive::addTree {
    my $self = shift;
 
    my ( $root, $dest, $pred, $compressionLevel );
    if ( ref( $_[0] ) eq 'HASH' ) {
        $root             = $_[0]->{root};
        $dest             = $_[0]->{zipName};
        $pred             = $_[0]->{select};
        $compressionLevel = $_[0]->{compressionLevel};
    }
    else {
        ( $root, $dest, $pred, $compressionLevel ) = @_;
    }
 
    return _error("root arg missing in call to addTree()")
      unless defined($root);
    $dest = '' unless defined($dest);
    $pred = sub { -r } unless defined($pred);
 
    my @files;
    my $startDir = $cwd_on_load;
 
    return _error( 'undef returned by _untaintDir on cwd ', $cwd_on_load )
      unless $startDir;
 
    # This avoids chdir'ing in Find, in a way compatible with older
    # versions of File::Find.
    my $wanted = sub {
        local $main::_ = $File::Find::name;
        my $dir = _untaintDir($File::Find::dir);
        chdir($startDir);
        if ( $^O eq 'MSWin32' && $Archive::Zip::UNICODE ) {
            push( @files, Win32::GetANSIPathName($File::Find::name) ) if (&$pred);
            $dir = Win32::GetANSIPathName($dir);
        }
        else {
            push( @files, $File::Find::name ) if (&$pred);
        }
        chdir($dir);
    };
 
    if ( $^O eq 'MSWin32' && $Archive::Zip::UNICODE ) {
        $root = Win32::GetANSIPathName($root);
    }
    File::Find::find( $wanted, $root );
 
    my $rootZipName = _asZipDirName( $root, 1 );    # with trailing slash
    my $pattern = $rootZipName eq './' ? '^' : "^\Q$rootZipName\E";
 
    $dest = _asZipDirName( $dest, 1 );              # with trailing slash
 
    foreach my $fileName (@files) {
        my $isDir;
        if ( $^O eq 'MSWin32' && $Archive::Zip::UNICODE ) {
            $isDir = -d Win32::GetANSIPathName($fileName);
        }
        else {
            $isDir = -d $fileName;
        }
 
        # normalize, remove leading ./
        my $archiveName = _asZipDirName( $fileName, $isDir );
        if ( $archiveName eq $rootZipName ) { $archiveName = $dest }
        else { $archiveName =~ s{$pattern}{$dest} }
        next if $archiveName =~ m{^\.?/?$};         # skip current dir
        my $member = $isDir
          ? $self->addDirectory( $fileName, $archiveName )
          : $self->addFile( $fileName, $archiveName );
        $member->desiredCompressionLevel($compressionLevel);
 
        return _error("add $fileName failed in addTree()") if !$member;
    }
    return AZ_OK;
}

1;