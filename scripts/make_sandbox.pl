#/usr/bin/perl -w 
use strict;
use warnings;
use File::Spec;
use File::Temp qw(tempfile);
use Getopt::Long qw(:config no_ignore_case);

use CorTeX::Util::DB_File_Utils qw(db_file_connect db_file_disconnect get_db_file_field);
use CorTeX::Backend;

use Data::Dumper;


my ($corpus, $service, $format, $limit) = ('modern', 'TeX to HTML', 'html', 10000);

GetOptions(
  "corpus=s" => \$corpus,
  "service=s" => \$service,
  "format=s" => \$format,
  "limit=i" => \$limit
) or pod2usage(-message => 'make_sandbox', -exitval => 1, -verbose => 0, -output => \*STDERR);

# Obtain a CorTeX backend
my $db_handle = db_file_connect();
my $backend = CorTeX::Backend->new(%$db_handle);
db_file_disconnect($db_handle);

my $taskdb = $backend->taskdb;
my $service_iid = $taskdb->serviceid_to_iid($taskdb->service_to_id($service));

my $ok_entries = $taskdb->get_custom_entries({severity=>"ok",limit=>$limit,
                                           corpus=>$corpus,service=>$service}) || [];
my @entry_list = map {$_->[0]} @$ok_entries;
my $limit_remainder = $limit - scalar(@entry_list);

if ($limit_remainder > 0) {
  my $warning_entries = $taskdb->get_custom_entries({severity=>"warning",category=>'not_parsed',limit=>$limit,
                                             corpus=>$corpus,service=>$service}) || [];
  push @entry_list, map {$_->[0]} @$warning_entries; }

# Now, archive all HTML files in the respective repositories in a single tarball:
my @result_files = map {result_entry($_,$service_iid)} @entry_list;

# Create a tar of the files:
unlink('sandbox.tar');
system('touch sandbox.tar');
foreach my $filepath(@result_files) {
  my ($volume,$dir,$name) = File::Spec->splitpath( $filepath );
  system('tar','-rvf','sandbox.tar',"-C$dir","$name"); }

sub result_entry {
  my ($entry,$service) = @_;
  my ($volume,$dir,$name) = File::Spec->splitpath( $entry );
  $service = '' if (!$service || ($service =~ /^import_v/));
  $service = "_cortex_$service" if $service;
  my $directory = File::Spec->catdir($entry,$service);
  # We have a simple (1 file) and a complex (1 archive) case:
  return File::Spec->catfile($directory,"$name.$format"); } 
