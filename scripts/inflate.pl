#/usr/bin/perl -w
use strict;
use warnings;
use File::Path qw(make_path);
use LaTeXML;
use LaTeXML::Common::Config;

# Author: Deyan Ginev
# Whatitdoes: Rewrite a snapshot of ZBL abstracts (in one text file) 
#             to separate LaTeX sources
# Input:  1. Snapshot file (e.g. /arXMLiv/zbl/dvd/export)
#         2. Extraction directory (e.g. /arXMLiv/zbl/sources)

my $snapshot = shift||"../2005-2011.txt";
my $target = shift||"../ZBL-corpus/";

#Make sure we have a slash in the end
$target=~s/(\/+)$//;
$target.="/";

open(my $snapshot_fh,"<",$snapshot);
my %doc=();

# Spare the File System, 200 files per folder
my $threshold = 200;
my $count = 0;
my $total = 0;
my $l1=1;
my $l2=1;
# Initialize a LaTeXML converter for ZBL:
our $config=LaTeXML::Common::Config->new(local=>1,timeout=>120,profile=>'zbl');
$config->check;
my $converter = LaTeXML->get_converter($config);
$converter->prepare_session($config);

my $previous;
print STDERR "[".localtime()."] Starting ZBL corpus inflation.\n";
while (<$snapshot_fh>) {
  my $line=$_;
  next if $line=~/^:_/;
  chomp $line;
  if ($line ne '::::') {
    # Extract structured data from the ZBL dump lines:
    $line=~/^\:([^:]+)\:\t(.*)$/;
    if ($1) {
      $previous=$1;
      $doc{lc($1)}=$2; }
    else { # Multiline content, append to previous entry:
      $doc{lc($previous)}.= "\n$line"; }  }
  else {
    # 2.0. End of current abstract, convert:
    $total++;
    print STDERR "[".localtime()."] Processed: $total\n" unless ($total % 500);
    #      print STDERR Dumper(%doc),"\n\n"; exit;
    my $content;
    # 2.1. First, construct the TeX file and reset the %doc metadata buffer:
    my ($name,$number,$author,$title,$published,
      $abstract,$doctype,$class,$keywords,$language) =
      map($_||"",map($doc{$_},('zn','an','au','ti','py','ab/en','dt','cc','ut','la')));
    # New vocabulary:
    $abstract = $doc{tx} unless $abstract;
    $name = $doc{id} unless $name;
    $number = $doc{id} unless $number;
    # If we have an abstract, write convert to HTML and write:
    undef %doc;
    %doc = ();
    if ($abstract) {
      $name = $number unless $name; #Make sure there's a filename
      $number = $name unless $number; #and vice versa for id
      $language = ($language) ? "\\language{$language}\n" : "";
      $class = ($class) ? "\\class{$class}\n" : "";
      $keywords = ($keywords) ? "\\keywords{$keywords}\n" : "";
      $doctype = ($doctype) ? "\\doctype{$doctype}\n" : "";
      
      my $tex = "literal:\n"
      . $language
      . $class
      . $keywords
      . $doctype
      . "\\aunotiso{$number}{$author}{$title}{$published}\n"
      . "\\beginreview\n"
      . $abstract . "\n"
      . "\\endreview{}\n";

      # 2.2. Convert to HTML5:
      my $response = $converter->convert($tex);
      my ($document, $status, $log) = map { $response->{$_} } qw(result status_code log) if defined $response;
      if (defined $document) {
        # Write down the HTML document:
        make_path("$target/$l1/$l2/$name/");
        open(my $html_fh,">","$target/$l1/$l2/$name/$name.xhtml");
        print $html_fh $document;
        close($html_fh);
      
        # 2.5. Update file counters:
        $count++;
        if ($count>=$threshold) {
          $count=0;
          $l2++;
        }
        if ($l2 >= $threshold) {
          $l2=1;
          $l1++;
        }
      }
    }
  }
}
close($snapshot_fh);
print STDERR "\n[".localtime()."] Total: $total\n";