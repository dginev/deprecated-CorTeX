#/usr/bin/perl -w 
use strict;
use warnings;
use File::Spec;
use File::Path qw(make_path remove_tree);
use Getopt::Long qw(:config no_ignore_case);
use XML::LibXML;
use XML::LibXML::XPathContext;
use HTML::HTML5::Parser;

use CorTeX::Util::DB_File_Utils qw(db_file_connect db_file_disconnect get_db_file_field);
use CorTeX::Backend;

use Data::Dumper;


my ($corpus, $service, $format, $limit, $destination, $split) = ('modern', 'TeX to HTML', 'html', 10000,'.',undef);

GetOptions(
  "corpus=s" => \$corpus,
  "service=s" => \$service,
  "format=s" => \$format,
  "split=s" => \$split,
  "limit=i" => \$limit,
  "destination=s" => \$destination
) or pod2usage(-message => 'make_sandbox', -exitval => 1, -verbose => 0, -output => \*STDERR);

my $selector = '//*[contains(@class,"'.$split.'")]' if $split;
my $html5_destination = File::Spec->catdir($destination,'html5');
my $xhtml5_destination = File::Spec->catdir($destination,'xhtml5');

# Obtain a CorTeX backend
my $db_handle = db_file_connect();
my $backend = CorTeX::Backend->new(%$db_handle);
db_file_disconnect($db_handle);

my $taskdb = $backend->taskdb;
my $service_iid = $taskdb->serviceid_to_iid($taskdb->service_to_id($service));

my $ok_entries = $taskdb->get_custom_entries({severity=>"ok",limit=>2*$limit,
                                           corpus=>$corpus,service=>$service}) || [];
my @entry_list = map {$_->[0]} @$ok_entries;
my $limit_remainder = 2*$limit - scalar(@entry_list);

if ($limit_remainder > 0) {
  my $warning_entries = $taskdb->get_custom_entries({severity=>"warning",category=>'not_parsed',limit=>$limit_remainder,
                                             corpus=>$corpus,service=>$service}) || [];
  push @entry_list, map {$_->[0]} @$warning_entries; }

# Now, archive all HTML files in the respective repositories in a single tarball:
my @result_files = map {result_entry($_,$service_iid)} @entry_list;

# Create two sandbox directories if we are splitting:
if ($split) {
  unlink('sandbox_HTML5.tar.gz');
  unlink('sandbox_XHTML5.tar.gz');
  make_path($html5_destination);
  make_path($xhtml5_destination); }
else {
  unlink('sandbox.tar');
  touch('sandbox.tar'); }
my $counter=0;
foreach my $filepath(@result_files) {
  next unless (-f $filepath && (! -z $filepath));
  $counter++;
  print STDERR "Processing document $counter\n";
  my ($volume,$dir,$name) = File::Spec->splitpath( $filepath );
  # If we want the file split into sub-elements, we should do so here:
  if ($split && $selector) {
    local $XML::LibXML::setTagCompression = 1;
    my $base_name = $name;
    $base_name =~ s/(\.[^.]+)$//;
    my $doc = HTML::HTML5::Parser->new()->parse_file($filepath, {encoding=>'utf-8',recover=>1});
    my $xpc = XML::LibXML::XPathContext->new($doc->documentElement);
    my @fragments = $xpc->findnodes($selector);
    my ($this_html5_destination, $this_xhtml5_destination);
    if (scalar(@fragments)) {
      $this_html5_destination = File::Spec->catdir($html5_destination,$base_name);
      $this_xhtml5_destination = File::Spec->catdir($xhtml5_destination,$base_name);
      mkdir($this_html5_destination);
      mkdir($this_xhtml5_destination); }
    my $split_counter=0;
    foreach my $fragment(@fragments) {
      $split_counter++;
      my $serialized = $fragment->toString(1);
      my $split_name = "$base_name"."_$split"."_$split_counter";
      my $html5_filepath = File::Spec->catfile($this_html5_destination,"$split_name.html");
      my $xhtml5_filepath = File::Spec->catfile($this_xhtml5_destination,"$split_name.xhtml");
      # Print the HTML5 serialization:
      open(my $html_fh, ">", $html5_filepath);
      binmode($html_fh,':encoding(UTF-8)');
      print $html_fh "<!DOCTYPE html><html><head>\n<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\"></head><body>\n"
        . $serialized
        . "\n</body></html>\n";
      close $html_fh;

      # Now the XHTML5 serialization:
      open(my $xhtml_fh, ">", $xhtml5_filepath);
      binmode($xhtml_fh,':encoding(UTF-8)');
      print $xhtml_fh '<?xml version="1.0" encoding="utf-8"?>'."\n"
        . "<html xmlns=\"http://www.w3.org/1999/xhtml\">\n<head>\n"
        . "<meta http-equiv=\"Content-Type\" content=\"application/xhtml+xml; charset=UTF-8\" /></head><body>\n"
        . $serialized
        . "\n</body></html>\n";
      close $xhtml_fh; } }
  else {
    system('tar','-rvf','sandbox.tar',"-C$dir","$name"); }
  last if $counter>=$limit; }

if ($split) {
  # tar.gz the two directories:
  system('tar','-czvf','sandbox_HTML5.tar.gz',"-C$destination","html5");
  system('tar','-czvf','sandbox_XHTML5.tar.gz',"-C$destination","xhtml5");
  remove_tree($html5_destination);
  remove_tree($xhtml5_destination); }

sub result_entry {
  my ($entry,$service) = @_;
  my ($volume,$dir,$name) = File::Spec->splitpath( $entry );
  $service = '' if (!$service || ($service =~ /^import_v/));
  $service = "_cortex_$service" if $service;
  my $directory = File::Spec->catdir($entry,$service);
  # We have a simple (1 file) and a complex (1 archive) case:
  return File::Spec->catfile($directory,"$name.$format"); } 
