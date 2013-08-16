#/usr/bin/perl -w
use strict;
use warnings;
use IO::Socket;
use Carp;
use Storable qw(freeze thaw);
use LaTeXML;

my $src = '/home/dreamweaver/svn/MathSearch/src';
my $opts={
	  identity => "latexml_zbl (LaTeXML version $LaTeXML::VERSION)",
	  profile => 'fragment',
	  'input_limit' => 1000,
	  timeout => 60,
	  port => 3354,
          format => 'xhtml',
          math_formats => ['pmml','cmml'],
          force_ids=>1,
          post=>1,
          stylesheet=>'../xsl/zbl2html.xsl',
          preload=>['zbl.cls'],
          paths=>['.',"$src/sty/","$src/rnc/"],
          local=>1,
	 };

my $corpus = shift || "$src/corpus";
$corpus=~s/\/$//g;
my $count=0;

#Startup daemon
system('latexmls','--port='.$opts->{port},'--timeout='.$opts->{timeout},'--autoflush='.$opts->{input_limit});

# 2 level descent:
my @dirs1 = grep(dirtest("$corpus/$_"),rdir($corpus));
foreach my $l1(@dirs1) {
  my @dirs2 = grep(dirtest("$corpus/$l1/$_"),rdir("$corpus/$l1"));
  foreach my $l2(@dirs2) {
    my @sources = grep(textest("$corpus/$l1/$l2/$_"),rdir("$corpus/$l1/$l2"));
    foreach my $source(@sources) {
      # Convert $source:
      my $base = "$corpus/$l1/$l2/$source";
      $base =~ s/\.tex$//;
      next if -e "$base.log"; # Skip done work!
      $opts->{destination}="$base.xhtml";
      $opts->{log}="$base.log";
      $opts->{source}="$base.tex";

      # Record if destination exists, for summary
      my $deststat = (stat($opts->{destination}))[9] if ($opts->{destination});
      $deststat = 0 unless $deststat;


      my $sock = new IO::Socket::INET
        ( PeerAddr => '127.0.0.1',
          PeerPort => $opts->{port},
          Proto => 'tcp',
        ); #Attempt connecting to a service
      if (!$sock) {
        # Boot a new one:
        system('latexmls','--port='.$opts->{port},'--timeout='.$opts->{timeout},'--autoflush='.$opts->{input_limit});
        $sock = new IO::Socket::INET
          ( PeerAddr => '127.0.0.1',
            PeerPort => $opts->{port},
            Proto => 'tcp',
          ); #Attempt connecting to a service
        croak "Could not create socket: $!\n" unless $sock;
      }

      my ($response,$batch);
      $sock->send(freeze($opts)."\nEND REQUEST\n");
      do {
        $sock->recv($batch,1024);
        $response.=$batch;
      } while ($batch);
      close($sock);
      if (! defined $response) {
        open(LOG,">",$opts->{log}) or croak "Couldn't open log file ".$opts->{log}.": $!\n";
        print LOG "Fatal error: Received empty response from LaTeXML Server!";
        close LOG;
        next;
      }
      $response = thaw($response);
      my ($result, $status, $log) = map { $response->{$_} } qw(result status log) if defined $response;

      if ($log) {
        open(LOG,">",$opts->{log}) or croak "Couldn't open log file ".$opts->{log}.": $!\n";
        print LOG $log;
        close LOG;
      }

      if ($result) {
        open(OUT,">",$opts->{destination}) or croak "Couldn't open output file ".$opts->{destination}.": $!";
        print OUT $result;
        close OUT;
      }

      # Print summary, if requested, to STDERR
      print STDERR $status;
      print STDERR summary($opts->{destination},$deststat);

      $count++;
      if (! ($count % 200)) {
        print STDERR "\n\n\n\n\nProcessed $count files...\n\n\n\n\n";
      }
    }
  }
}


# == Helpers ==
sub dirtest {
  (-d $_[0]) && ($_ !~ /^\./);
}

sub textest {
  (-e $_[0]) && ($_[0] !~ /^\.[^.]/) && ($_[0] =~ /\.tex$/);
}

sub rdir {
 opendir(IN,$_[0]);
 my @contents = sort(readdir(IN));
 closedir(IN);
 @contents;
}

sub summary {
  my ($dest,$deststat) = @_;
  my $newstat = (stat($dest))[9];
  $newstat = 0 unless $newstat;
  if ($newstat && ($deststat != $newstat)) { "\nWrote $dest\n"; }
  else { "\nError! Did not write file $dest\n"; }
}
