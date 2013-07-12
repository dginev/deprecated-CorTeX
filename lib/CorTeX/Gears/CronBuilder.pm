# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | Cron Job Builder Module                                              | #
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
package CorTeX::Gears::CronBuilder;
use warnings;
use strict;
use Data::Dumper;
use Encode;
use List::Util 'shuffle';

use CorTeX::Temporal::Backend;
use CorTeX::Util::Convert qw(convert_snippet convert_zip log_to_triples);

{ # begin local group, to catch signals
local $SIG{'INT'} = \&_stop_all_jobs; # Interrupt handler
local $SIG{'HUP'} = \&_stop_all_jobs; # Apache Hangup handler
local $SIG{'KILL'} = \&_stop_all_jobs; # Just good-old KILL handler

our $batch_size = 100;

sub new {
  my ($class,%opts)=@_;
  $opts{main_repos} = 'buildsys' unless defined $opts{main_repos};
  $opts{meta_graph} = 'meta' unless defined $opts{meta_graph};
  $opts{entry_type} = 'complex' unless defined $opts{entry_type};
  bless {%opts}, $class;
}

sub start {
  my ($self) = @_;
  while (1) {
    my $proxy_url = $self->{proxy_url};
    my $exist = $self->{backend}->exist;
    my $sesame = $self->{backend}->sesame;
    my $entry_response = $sesame->get_queued_entries($self->{main_repos},$batch_size*($self->{query_size}));
    my $results = $entry_response && $entry_response->{results}->[0]->{result};
    unless ($results && @$results) { print STDERR "Nothing to process, 1 minute nap\n"; sleep 60; next; }
    my @URLs;
    if (scalar(@{$results})>$batch_size) {
      my $index = int(rand($self->{query_size}-1));
      # Pick entries from @$results
      @URLs = map {$_->{binding}->{uri}} @{$results}[ ($index*$batch_size) .. (($index+1)*$batch_size) ];
    } else {
      # Take all $results
      @URLs = map {$_->{binding}->{uri}} @$results;
    }
    $sesame->mark_entries_queued({priority=>'-1',entries=>\@URLs,graph=>$self->{meta_graph},repository=>$self->{main_repos}});
    my $triples = [];
    my $entries_done = [];
    foreach my $entry(@URLs) {
      my $wait_required = 0;
      print STDERR "Will convert $entry, with PID ",$$,"\n";
      my $collection = $entry;
      # TODO: More robust code is needed here, this is going to be hard to maintain!!!
      $collection =~ s/exist:/\/db\//;
      $collection =~ /^(.+\/)([^\/]+)(\/)?$/;
      my $strip_prefix = $1;
      my $base_name = $2;
      if ($self->{entry_type} eq 'simple') {
        # Simple, single-file workflow
        my $tex_doc = "$collection/".$base_name.".tex";
        my $xhtml_doc = "$collection/".$base_name.".xhtml";
        my $log_doc = "$collection/".$base_name.".log";
        my $content;
        do {
          $content = $exist->get_binary_doc($tex_doc);
          if (! defined $content) {
            print STDERR "Failed to fetch content, napping 1 minute...";
            sleep 60;
          }
        } while (! defined $content);
        my $response = convert_snippet(payload=>$content,
                                      converter=>$self->{converter},
                                      proxy_url=>$proxy_url);
        # First, mark entry as done
        push @$entries_done, $entry;
        if ($response) {
          $exist->insert_doc(payload=>encode('UTF-8',$response->{result}),
                             extension=>'xhtml',
                             db_pathname=>$xhtml_doc) if $response->{result};
          $exist->insert_doc(payload=>encode('UTF-8',$response->{log}),
                             extension=>'log',
                             db_pathname=>$log_doc) if $response->{log};
          if (!$response->{log}) {
            $response->{log} = "Status:conversion:3\nFatal:conversion:empty-result Something broke, got no XML result or Log content." unless $response->{result}; 
            $response->{log} = "Status:conversion:3\nFatal:conversion:empty-log Something broke, got no Log content." unless $response->{log};
          }
          my $log_triples = log_to_triples($entry,$response->{log});
          push $triples, @$log_triples;
        } else {
          # Something failed, mark Fatal:
          my $log_triples = log_to_triples($entry,"Status:conversion:3\nFatal:buildsys:no-response Something broke, got no response.");
          push $triples, @$log_triples;
          $wait_required++;
        }
      }
      else {
        # Complex, ZIP-based workflow:
        my $zip_name = $base_name.'.zip';
        print STDERR " Entry to process : $collection, Name: $zip_name\n";
        my $response = $exist->query("compression:zip(xs:anyURI('".$collection."'),xs:boolean('true'),'".$strip_prefix."')");
        my $zip = $response->{first};
        my $converted_zip = convert_zip(converter=>$self->{converter},
                                      payload=>$zip,
                                      name=>$zip_name,
                                      proxy_url=>$proxy_url);
        # Unzip has to be manual for now, figure out something smarter (Java?) later
        $collection =~ /^(.+\/)([^\/]+)(\/)?$/;
        my $base_collection = $1;
        my $unzip_xquery = unzip_xquery($converted_zip,$base_collection);
        $response = $exist->query($unzip_xquery);
        # First, mark entry as done
        push @$entries_done, $entry;
        if ($response->{first}) {
          # The conversion succeeded, so parse the log, add triples and switch priority to 0
          my $log_pathname = "$base_collection$base_name/$base_name.log";
          my $log_content = $exist->get_binary_doc($log_pathname) || "Status:conversion:3\nFatal:buildsys:empty-log Something broke, got no log content.";
          my $log_triples = log_to_triples($entry,$log_content);
          push $triples, @$log_triples;
        } else {
          # Something failed, mark Fatal:
          my $log_triples = log_to_triples($entry,"Status:conversion:3\nFatal:buildsys:no-response Something broke, got no response.");
          push $triples, @$log_triples;
          $wait_required++;
        }
      }
      if ($wait_required) {
        $sesame->mark_entries_done({entries=>$entries_done,graph=>$self->{meta_graph},repository=>$self->{main_repos}});
        $sesame->add_triples({triples=>$triples,graph=>$self->{meta_graph},repository=>$self->{main_repos}});
        $triples = []; $entries_done=[];
        wait_until_available($self->{converter});
      }
    }
    $sesame->mark_entries_done({entries=>$entries_done,graph=>$self->{meta_graph},repository=>$self->{main_repos}});
    $sesame->add_triples({triples=>$triples,graph=>$self->{meta_graph},repository=>$self->{main_repos}});
  }
}

sub _stop_all_jobs {
  print STDERR "Received Interrupt! Terminating...\n";
  # TODO, Make this graceful, let all conversions finish first
  exit 0;
}

sub wait_until_available {
  my ($url) = @_;
  sleep 1;
  my $code = 404;
  while (1) {
    my $code = Mojo::UserAgent->new->post($url)->res->code;
    if ($code && ($code == 200)) {
      last;
    } else {
      sleep 60;
    }
  }
}

sub unzip_xquery {
  my ($zip,$base_collection)=@_;
  my $declarations = <<'EOL';
declare namespace fw = "http://www.cems.uwe.ac.uk/xmlwiki/fw";
declare function fw:filter($path as xs:string, $type as xs:string, $param as item()*) as xs:boolean {
   if (ends-with($path,".tex")) then false() else true()
};

declare function fw:process($path as xs:string,$type as xs:string, $data as item()? , $param as item()*) {
  let $steps := tokenize($path,"/")
  let $nsteps := count($steps)
  let $filename := $steps[$nsteps]
  let $collection := string-join(subsequence($steps,1,$nsteps - 1 ),"/")
  let $baseCollection := string($param/@collection)
  let $fullCollection := concat($baseCollection,$collection)
  let $mkdir := 
   if (xmldb:collection-exists($fullCollection)) then () 
    else xmldb:create-collection($baseCollection, $collection)
  let $filename := xmldb:encode($filename)
  return
  if (count($data)>0) then
    if (matches($filename,"xhtml$")) then
           xmldb:store($fullCollection, $filename, $data, "application/xhtml+xml")
    else if (matches($filename,"html$")) then
           xmldb:store($fullCollection, $filename, $data, "text/html")
    else if (matches($filename,"log$")) then
           xmldb:store($fullCollection, $filename, $data, "text/plain")
    else if (matches($filename, "xml$")) then 
           xmldb:store($fullCollection, $filename, $data, "application/xml")
    else if (matches($filename,"png$")) then
           xmldb:store($fullCollection, $filename, $data, "image/png")
    else if (matches($filename,"jpg|jpeg$")) then
           xmldb:store($fullCollection, $filename, $data, "image/jpeg")
    else if (matches($filename,"gif$")) then
           xmldb:store($fullCollection, $filename, $data, "image/gif")
    else
           xmldb:store($fullCollection, $filename, $data, "application/octet-stream")
 else 0
};

let $filter := util:function(QName("http://www.cems.uwe.ac.uk/xmlwiki/fw","fw:filter"),3)
let $process := util:function(QName("http://www.cems.uwe.ac.uk/xmlwiki/fw","fw:process"),4)

EOL

my $invoke = 'let $xml := compression:unzip(xs:base64Binary("'.$zip.'"),$filter,(),$process,<param collection="'.$base_collection.'"/>)'."\n"
.'return <status>{$xml}</status>';

return $declarations.$invoke;
}


} # end local group
1;

__END__

=pod 

=head1 NAME

C<CorTeX::Gears::CronBuilder> - Main Scheduler

=head1 SYNOPSIS

    use CorTeX::Gears::CronBuilder;
    

=head1 DESCRIPTION

TODO: add me

=head2 METHODS

=over 4

=item C<< TODO: add all>>

=back

=head1 AUTHOR

Deyan Ginev <d.ginev@jacobs-university.de>

=head1 COPYRIGHT

 Research software, produced as part of work done by 
 the KWARC group at Jacobs University Bremen.
 Released under the GNU Public License

=cut
