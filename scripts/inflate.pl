#/usr/bin/perl -w
use strict;
use warnings;
use File::Path qw(make_path);
use Data::Dumper;

# Author: Deyan Ginev
# Whatitdoes: Rewrite a snapshot of ZBL abstracts (in one text file) 
#             to separate LaTeX sources
# Input:  1. Snapshot file (e.g. /arXMLiv/zbl/dvd/export)
#         2. Extraction directory (e.g. /arXMLiv/zbl/sources)

my $snapshot = shift||"../2005-2011.txt";
my $target = shift||"../ZBL-corpus/";

#Make sure we have a slash in the end
$target=~s/\/$//g;
$target.="/";


open(SNAPSHOT,"<".$snapshot);
my %doc=();

# Spare the File System, 200 files per folder
my $threshold = 200;
my $count = 0;
my $total = 0;
my $l1=1;
my $l2=1;

my $empty=0;
my $previous;

while (<SNAPSHOT>) {
    my $line=$_;
    if ($line=~/^\s*$/) { $empty++; } else {

      chomp $line;
      $line=~/^([A-Z]{2})\:\t(.*)$/;
      if ($1) {
        $previous=$1;
        if ($empty<2) {
          $doc{lc($1)}=$2;
          $empty=0;
        }
        else {
          $empty=0;
          #End of current abstract, convert:
          $total++;
          print "Processed: $total\n" unless ($total % 500);
          #      print STDERR Dumper(%doc),"\n\n"; exit;
          my $content;
          my ($name,$number,$author,$title,$published,
              $abstract,$doctype,$class,$keywords,$language)=
            map($_||"",map($doc{$_},('zn','an','au','ti','py','ab','dt','cc','ut','la')));
          undef %doc; %doc=(lc($1)=>$2);
          if ($abstract && ($abstract!~/^not reviewed$/i)) {
            $name = $number unless $name; #Make sure there's a filename
            $number = $name unless $number; #and vice versa for id
            $language = ($language) ? "\\language{$language}\n" : "";
            $class = ($class) ? "\\class{$class}\n" : "";
            $keywords = ($keywords) ? "\\keywords{$keywords}\n" : "";
            $doctype = ($doctype) ? "\\doctype{$doctype}\n" : "";
        
            #Write TeX file for this abstract:
            my $tex = "\n"
          . $language
  	  . $class
	  . $keywords
	  . $doctype
	  . "\\aunotiso{$number}{$author}{$title}{$published}\n"
	  . "\\beginreview\n"
	  . $abstract . "\n"
	  . "\\endreview{}\n";
            make_path("$target/$l1/$l2/$name/");
            open(T,">","$target/$l1/$l2/$name/$name.tex");
            print T $tex;
            close(T);
            # Update counters:
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
      else { # Multiline content, append to previous entry:
        $doc{lc($previous)}.="\n" foreach ($empty);
        $empty=0;
        $doc{lc($previous)}.= "\n$line";
      } 
    }
  }
close(SNAPSHOT);

print "\n";
print "Total: $total\n";
#Metadata keys: dt zn ut ab ti la au cc py an
# Field	Long form	Description
# au	author	Index of authors, editors, and author references.
# ti	title	Index of original and translated title.
# cc	msc	Index of Mathematics Subject Classification (MSC 2000).
# ut	keyword	Index of uncontrolled terms and keywords.
# py	year	Index of publication year.
# la	language	Index of ISO 639-1 alpha-2 language code.
# dt	doctype	Index of document types. (j, b, a)
# j → journal article; b → book; a → book article
# an	zblno	Index of Zentralblatt MATH identifier and document (DE) number.
        #(zn)
