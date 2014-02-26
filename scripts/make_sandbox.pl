#/usr/bin/perl -w 
use strict;
use warnings;
use File::Spec;
use Getopt::Long qw(:config no_ignore_case);
use XML::LibXML;
use XML::LibXML::XPathContext;
use HTML::HTML5::Parser;

use CorTeX::Util::DB_File_Utils qw(db_file_connect db_file_disconnect get_db_file_field);
use CorTeX::Backend;

use Data::Dumper;


my ($corpus, $service, $format, $limit, $split) = ('modern', 'TeX to HTML', 'html', 10000);

GetOptions(
  "corpus=s" => \$corpus,
  "service=s" => \$service,
  "format=s" => \$format,
  "split=s" => \$split,
  "limit=i" => \$limit
) or pod2usage(-message => 'make_sandbox', -exitval => 1, -verbose => 0, -output => \*STDERR);

my $selector = '//*[contains(@class,"'.$split.'")]' if $split;

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

# Create a tar of the files:
unlink('sandbox.tar');
system('touch sandbox.tar');
my $counter=0;
foreach my $filepath(@result_files) {
  next unless (-f $filepath && (! -z $filepath));
  $counter++;
  my ($volume,$dir,$name) = File::Spec->splitpath( $filepath );
  # If we want the file split into sub-elements, we should do so here:
  if ($split && $selector) {
    my $base_name = $name;
    $base_name =~ s/(\.[^.]+)$//;
    my $doc = HTML::HTML5::Parser->new()->parse_file($filepath, {encoding=>'utf-8',recover=>1});
    $doc->setEncoding('UTF-8');
    my $xpc = XML::LibXML::XPathContext->new($doc->documentElement);
    my @fragments = $xpc->findnodes($selector);
    my $split_counter=0;
    foreach my $fragment(@fragments) {
      $split_counter++;
      my $split_name = "$base_name"."_$split"."_$split_counter.html";
      my $split_filepath = File::Spec->catfile($dir,$split_name);
      open(my $split_fh, ">", $split_filepath);
      binmode($split_fh,':encoding(UTF-8)');
      print $split_fh "<!DOCTYPE html><html><head>\n<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\" /></head><body>\n";
      print $split_fh $fragment->toString(1);
      print $split_fh "\n</body></html>\n";
      system('tar','-rvf','sandbox.tar',"-C$dir","$split_name");
      unlink($split_filepath); } }
  else {
    system('tar','-rvf','sandbox.tar',"-C$dir","$name"); }
  last if $counter>=$limit; }

sub result_entry {
  my ($entry,$service) = @_;
  my ($volume,$dir,$name) = File::Spec->splitpath( $entry );
  $service = '' if (!$service || ($service =~ /^import_v/));
  $service = "_cortex_$service" if $service;
  my $directory = File::Spec->catdir($entry,$service);
  # We have a simple (1 file) and a complex (1 archive) case:
  return File::Spec->catfile($directory,"$name.$format"); } 
