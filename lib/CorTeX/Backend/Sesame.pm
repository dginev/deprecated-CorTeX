# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | Sesame Triple Store Backend Connector                               | #
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
package CorTeX::Backend::Sesame;

use warnings;
use strict;

use Carp;
use XML::Simple qw(:strict);
use Data::Dumper;
use Mojo::UserAgent;
use CorTeX::Util::RDFWrappers qw(:all);
use feature qw(switch);

sub new {
 my ($class,%opts)=@_;
 $opts{url} = $opts{sesame_url}||'localhost:8080/openrdf-sesame';
 $opts{url} =~ s/\/+$//; # No trailing slash
 $opts{repositories_url} = $opts{url}.'/repositories';
 $opts{exist_base} = $opts{exist_url}||'http://localhost:8080/exist';
 $opts{exist_base} =~ s/\/+$//;  # No trailing slashes
 $opts{userAgent} = Mojo::UserAgent->new;
 my $response = $opts{userAgent}->head($opts{url});
 my $found = ($response->res->code == 302); # Found HTTP code = 302
 if ($found) {
  return bless {%opts}, $class;}
 else {
  return; }
}

### Convenience getters ###
sub userAgent {  $_[0]->{userAgent}; }
sub URL { $_[0]->{url}; }
sub URL_repositories {  $_[0]->{repositories_url}; }
sub URL_exist { $_[0]->{exist_base}; }
sub mk_graph_url { $_[0]->{repositories_url}.'/'.$_[1].'/rdf-graphs/'.$_[2]; }
sub mk_statements_url { $_[0]->{repositories_url}.'/'.$_[1].'/statements'; }
sub mk_contexts_url { $_[0]->{repositories_url}.'/'.$_[1].'/contexts'; }


### Core communication ###
our $HTTP_Headers = {
 'sparql-results+xml'=>{Accept=>'application/sparql-results+xml;charset=UTF-8',
      'Content-Type' => 'application/sparql-results+xml;charset=UTF-8'},
 'turtle' => {'Content-Type' => 'application/x-turtle;charset=UTF-8'},
 'update' => {'Content-Type' => 'application/x-www-form-urlencoded'},
 'query' => {'Content-Type'=>'application/x-www-form-urlencoded',
       Accept=>'application/sparql-results+xml;charset=UTF-8',}
};
sub http_get {
  my ($self,$url) = @_;
  my $response = $self->userAgent->get($url => $HTTP_Headers->{'sparql-results+xml'});
  carp("Couldn't HTTP GET at $url \n") unless $response;
  return (defined $response) && $response->res->body;
}
sub http_post {
  my ($self,$url,$query,$headers) = @_;
  $headers = 'turtle' unless defined $headers;
  #print STDERR "QURL: $url\n";
  my $response = $self->userAgent->post($url => $HTTP_Headers->{$headers}  => $query);
  carp "Couldn't HTTP POST at $url \n" unless $response;
  #print STDERR "Q:$query\n\n";
  return ((defined $response) && ($response->res->body || 1));
}
sub http_delete {
  my ($self,$url) = @_;
  my $response = $self->userAgent->delete($url);
  carp "Couldn't HTTP DELETE at $url \n" unless $response;
  return ((defined $response) && ($response->res->body || 1));
}



### API Layer ###
sub repository_size {
  my ($self,$repository_ID) = @_;
  my $size_url = $self->URL_repositories.'/'.$repository_ID.'/size';
  my $size = $self->http_get($size_url);
  carp "Repository size request failed, got: '$size'\n" unless $size=~/^[-]?\d+$/;
  $size = -1 if ((!defined $size) || (length($size) == 0) || ($size =~ /unknown|error/i));
  return $size;
}

sub new_repository {
  my ($self,$name,$overwrite) = @_;
  if ($overwrite && ($self->repository_size($name) != -1)) {
    # If it exists, we will overwrite it!
    $self->delete_repository($name);
  }

  # We need to add the repository triples in the SYSTEM's repository context
  my $ref = $self->get_contexts('SYSTEM');
  carp "System context not found!" unless $ref;
  my $context = $ref->{results}->{result}->[0]->{binding}->{bnode};
  $context=~s/node/_:n/;

  my $query =
'@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#>.
@prefix rep: <http://www.openrdf.org/config/repository#>.
@prefix sr: <http://www.openrdf.org/config/repository/sail#>.
@prefix sail: <http://www.openrdf.org/config/sail#>.
@prefix owlim: <http://www.ontotext.com/trree/owlim#>.

<'.$self->URL_repositories.'/'.$name.'>  a rep:Repository ;
   rep:repositoryID "'.$name.'";
   rdfs:label "Build System Repository: '.$name.'";
   rep:repositoryImpl [
     rep:repositoryType "openrdf:SailRepository" ;
     sr:sailImpl [
       sail:sailType "swiftowlim:Sail" ;
       owlim:ruleset "rdfs-optimized" ;
       owlim:partialRDFS "true" ;
       owlim:noPersist "false" ;
       owlim:storage-folder "owlim-storage" ;
       owlim:new-triples-file "new-triples-file.nt" ;
       owlim:entity-index-size "1000000" ;
       owlim:jobsize "1000" ;
       owlim:repository-type "in-memory-repository" ;
     ]
   ].';
       #owlim:imports "./ontology/my_ontology.rdf" ;
       #owlim:base-URL "http://example.org#" ;
       #owlim:defaultNS "http://www.my-organisation.org/ontology#"


#   my $query =
#     '@prefix rep: <http://www.openrdf.org/config/repository#>.
# @prefix sr: <http://www.openrdf.org/config/repository/sail#>.
# @prefix sail: <http://www.openrdf.org/config/sail#>.
# @prefix ms: <http://www.openrdf.org/config/sail/memory#>.
# @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#>.

# <'.$self->URL_repositories.'/'.$name.'> a rep:Repository;
# rep:repositoryID "'.$name.'";
# rdfs:label "Build System Repository: '.$name.'";
# rep:repositoryImpl [
# rep:repositoryType "openrdf:SailRepository";
# sr:sailImpl [
# sail:sailType "openrdf:MemoryStore";
# ms:persist "true";
# ms:syncDelay "5"
# ]
# ].';

  $self->http_post($self->URL_repositories.'/SYSTEM/statements?context='.$context,  $query);
  #print STDERR "Repository creation response:\n",$tx->res->body,"\n" if ($self->{verbosity}>0);
  # TODO: We need to figure out if this succeeded!
}

sub delete_repository {
  my ($self,$repository) = @_;
  $self->http_delete($self->URL_repositories.'/'.$repository);
}

sub get_contexts {
  my ($self,$repository) = @_;
  my $contexts = $self->http_get($self->mk_contexts_url($repository));
  my $response_object = eval { XMLin($contexts,KeyAttr=>{},ForceArray=>['result']) };
  if ($@) {
    print STDERR "Malformed XML Response: ''$contexts''\n\t\tRaised error: $@\n\t\tAt SPARQL contexts GET request\n ";
    return;
  } else {
    return $response_object;
  }
}

sub add_triple {
  my ($self,$data)=@_;
  my ($subject,$predicate,$object,$graph,$repository) = map {$data->{$_}} 
    qw(subject predicate object graph repository);
  my $graphURL = $self->mk_graph_url($repository,$graph) if $graph;
  my $triple = wrap_Turtle_triple($subject,$predicate,$object,$self->{exist_base});
  $self->http_post($graphURL, $triple);
}

sub add_triples {
  my ($self,$data)=@_;
  my ($triples,$graph,$repository) = map {$data->{$_}} qw(triples graph repository);
  return unless @$triples;
  my $query = wrap_Turtle_triple(@{$triples->[0]},$self->{exist_base});
  $query .= wrap_Turtle_triple_noprefix(@{$triples->[$_]})."\n" foreach (1..$#$triples);
  my $graphURL = $self->mk_graph_url($repository,$graph) if $graph;
  #print STDERR "ADD TRIPLES : \n $query \n\n";
  $self->http_post($graphURL, $query);
}

sub update_triple {
  my ($self,$data)=@_;
  my ($old,$new,$where,$graph,$repository) = map {$data->{$_}} 
    qw(old new where graph repository);
  $where = $old unless $where;
  my $graphURL = $self->mk_graph_url($repository,$graph) if $graph;
  my $updateURL = $self->mk_statements_url($repository);
  my $query = wrap_SPARQL_Update($old,$new,$where,$graphURL,$self->{exist_base});
  #print STDERR "Q: $query\n\n";
  $self->http_post($updateURL, $query, 'update');
}
sub update_triples {
  my ($self,$data)=@_;
  my ($updates,$graph,$repository) = map {$data->{$_}} 
    qw(updates graph repository);
  my $graphURL = $self->mk_graph_url($repository,$graph) if $graph;
  my $updateURL = $self->mk_statements_url($repository);
  my $query = wrap_SPARQL_Updates($updates,$graphURL,$self->{exist_base});
  #print STDERR "Update Query:\n $query\n\n";
  $self->http_post($updateURL, $query, 'update');
}

sub mark_entry_done {
  my ($self,$data) = @_;
  my $old_triple = {
         subject=>$data->{entry},
         predicate=>"build:priority",
         object=>unique_varname()
  };
  my $new_triple = {
         subject=>$data->{entry},
         predicate=>"build:priority",
         object=>xsd(0)
  };
  $self->update_triple({old=>[$old_triple],new=>[$new_triple],where=>[$old_triple],%$data});
}
sub mark_entries_done {
  my ($self,$data) = @_;
  my $triples = [];
  foreach my $entry(@{$data->{entries}}) {
    my $old_triple = [{
         subject=>$entry,
         predicate=>"build:priority",
         object=>unique_varname()
    }];
    my $new_triple = [{
         subject=>$entry,
         predicate=>"build:priority",
         object=>xsd(0)
    }];
    push @$triples, {old=>$old_triple,new=>$new_triple};
  }
  $self->update_triples({updates=>$triples,graph=>$data->{graph},repository=>$data->{repository}}); 
}

sub mark_entry_queued {
  my ($self,$data) = @_;
  my ($x,$any,$anyp,$anyvalue,$anyblank) = (unique_varname(),unique_varname(),unique_varname(),unique_varname(),unique_varname());
  my $old_triple = [{
    subject=>$data->{entry},
    predicate=>"build:priority",
    object=>$x
  },{
    subject=>$data->{entry},
    predicate=>$any,
    object=>$anyblank,
    optional=>1
  },{
    subject=>$anyblank,
    predicate=>$anyp,
    object=>$anyvalue,
    optional=>1
    }];
  my $new_triple = [{
    subject=>$data->{entry},
    predicate=>"build:priority",
    object=>xsd($data->{priority})
  }];
  $self->update_triple({old=>$old_triple,new=>$new_triple,%$data});
}

sub mark_entries_queued {
  my ($self,$data) = @_;
  my $triples = [];
  foreach (@{$data->{entries}}) {
    my ($x,$any,$anyp,$anyvalue,$anyblank) = (unique_varname(),unique_varname(),unique_varname(),unique_varname(),unique_varname());
    my $old_triple = [{
      subject=>$_,
      predicate=>"build:priority",
      object=>$x
    },{
      subject=>$_,
      predicate=>$any,
      object=>$anyblank,
      optional=>1
    },{
      subject=>$anyblank,
      predicate=>$anyp,
      object=>$anyvalue,
      optional=>1
    }];
    my $new_triple = [{
      subject=>$_,
      predicate=>"build:priority",
      object=>xsd($data->{priority})
    }];
    push @$triples, {old=>$old_triple,new=>$new_triple};
  }
  $self->update_triples({updates=>$triples,graph=>$data->{graph},repository=>$data->{repository}}); 
}

our $severity_map = {
  ok => 0,
  warning => 1,
  error => 2,
  fatal => 3
};
sub mark_custom_entries_queued {
  my ($self,$data) = @_;
  my ($x,$any,$anyp,$anyvalue) = (unique_varname(),unique_varname(),unique_varname(),unique_varname());
  my ($anyblank,$blank,$statusblank) = (unique_varname(),unique_varname(),unique_varname());
  my $old_triple = [{
    subject=>$x,
    predicate=>'build:priority',
    object=>xsd(0)
  },{
    subject=>$x,
    predicate=>$any,
    object=>$anyblank
  },{
    subject=>$anyblank,
    predicate=>$anyp,
    object=>$anyvalue 
    }];
  my $new_triple = [{
    subject=>$x,
    predicate=>'build:priority',
    object=>xsd(1)
  }];
  # Where takes into account severity, category and what:
  my $where=[];
  if ($data->{severity}) {
    push @$where, {subject=>$x,predicate=>"build:status",object=>$statusblank};
    push @$where, {subject=>$statusblank,predicate=>"build:what",object=>xsd($severity_map->{$data->{severity}})};
    if ($data->{category}) {
      push @$where, {subject=>$x,predicate=>'build:'.$data->{severity},object=>$blank} if ($data->{severity} ne 'ok');
      push @$where, {subject=>$blank,predicate=>'build:category',object=>xsd($data->{category},get=>1)};
      if ($data->{what}) {
        push @$where, {subject=>$blank,predicate=>'build:what',object=>xsd($data->{what},get=>1)};
      }
    }
    #Mark to delete all previous results
    push @$where, {subject=>$x,predicate=>$any,object=>$anyblank, optional=>1};
    push @$where, {subject=>$anyblank,predicate=>$anyp,object=>$anyvalue,optional=>1};
  }
  $where = $old_triple unless scalar(@$where);
  # Then mark for rerun
  $self->update_triple({old=>$old_triple,new=>$new_triple,where=>$where,%$data});  
}

sub get_custom_entries {
  my ($self,$data)=@_;
  # Santiy: unescape data fields first
  $data->{what} = sesame_unescape($data->{what});
  $data->{category} = sesame_unescape($data->{category});
  $data->{severity} = sesame_unescape($data->{severity});
  # Retrieve the relevant entries from:to
  my $query = 'SELECT distinct ?x '.($data->{what} ? '?y' : '').' WHERE {?x build:priority "0"^^xsd:integer. ?x build:status ?statusblank. '
            . '?statusblank build:what '.xsd($severity_map->{$data->{severity}}).'. '
            . ( (($data->{severity} ne 'ok') && $data->{category}) ? 
                '?x build:'.$data->{severity}.' ?blank. '
                . '?blank build:category '.xsd($data->{category},get=>1).'. '
                . ($data->{what} ? 
                  '?blank build:what '.xsd($data->{what},get=>1).'. '
                  .'?blank build:details ?y. '
                  : '' )
              : '' )
            . " }\n"
            . "ORDER BY ?x\n"
            . ($data->{limit} ? "LIMIT ".$data->{limit}." \n" : '')
            . ($data->{from} ? "OFFSET ".$data->{from}." \n" : '');
            #. 'ORDER BY ?x';

  my @entries;
  my $xml_ref = $self->sparql_query({query=>$query,graph=>$data->{graph},repository=>$data->{repository}});
  if ($data->{severity} && $data->{category} && $data->{what}) {
    # Return pairs of results and related details message
    # TODO: Make sure this is always in the right order, not sure how reliably XML::Simple parses it 
    @entries = map {my $url = $_->{binding}->[1]->{uri};
                    my $name = $url;
                    $name =~ s/^exist:[^\/]+\///;
                    $url =~ s/^exist:/$self->{exist_base}."\/admin\/admin.xql;?panel=browse&collection=\/db\/"/e;
                    [$name, sesame_unescape($_->{binding}->[0]->{literal}->{content}), $url] } @{$xml_ref->{results}->[0]->{result}};
  } else {
    # Only return results
    @entries = map {my $url = $_->{binding}->{uri};
                    my $name = $url;
                    $name =~ s/^exist:[^\/]+\///;
                    $url =~ s/^exist:/$self->{exist_base}."\/admin\/admin.xql;?panel=browse&collection=\/db\/"/e;
                    [$name, undef, $url ]; }
       @{$xml_ref->{results}->[0]->{result}};
  }
  #print STDERR Dumper(@entries);
  \@entries;
}

sub mark_limbo_entries_queued {
  my ($self,$data) = @_;
  my $old_triple = {
    subject=>'?x',
    predicate=>'build:priority',
    object=>xsd(-1)
  };
  my $new_triple = {
    subject=>'?x',
    predicate=>'build:priority',
    object=>xsd(1)
  };
  $self->update_triple({old=>[$old_triple],new=>[$new_triple],where=>[$old_triple],%$data});
}


sub sparql_query {
  my ($self,$data)=@_;
  my ($query,$graph,$repository) = map {$data->{$_}} qw(query graph repository);
  my $graphURL = $self->mk_graph_url($repository,$graph) if $graph;
  #TODO: Figure out how to deal with the graphs
  my $queryURL = $self->URL_repositories.'/'.$repository;
  #print STDERR "QURL: $query\n";
  my $response = $self->http_post($queryURL, wrap_SPARQL_Query($query,$self->{exist_base}), 'query');
  #print STDERR "Response:\n",Dumper($response),"\n\n";
  my $response_object = eval { XMLin($response,KeyAttr=>{},ForceArray=>['results','result']) };
  if ($@) {
    print STDERR "Malformed XML Response: ''$response''\n\t\tRaised error: $@\n\t\tAt SPARQL query: $query\n ";
    return;
  } else {
    return $response_object;
  }
}

sub get_corpus_name {
  my ($self,$repository) = @_;
  my $query = 'SELECT ?x WHERE { ?x rdfs:type '.xsd("Corpus").' }';
  my $xml_ref = $self->sparql_query({query=>$query,repository=>$repository});
  my $name = ($xml_ref && $xml_ref->{results}->[0]->{result}->[0]->{binding}->{uri});
  $name =~ s/^.+\///; # A name should have no slashes;
  return ($name || 'unknown name');
}

sub get_queued_entries {
  my ($self,$repository,$limit) = @_;
  my $query = 'SELECT ?x WHERE { ?x build:priority ?priority. FILTER (?priority >= 1) }';#' ORDER BY DESC(?priority) ';
  $query .= ' LIMIT '.$limit if defined $limit;
  my $xml_ref = $self->sparql_query({query=>$query,repository=>$repository});
}

sub count_entries {
  my ($self,$repository,$status_word,$conditions) = @_;
  my ($priority,$status_code)=(undef,undef);
  given ($status_word) {
    when ("all")   { ($priority,$status_code) = ('?priority',''); }
    when ("queued")   { ($priority,$status_code) = ('?priority. FILTER (?priority >= 1)',''); }
    when ("reserved") { ($priority,$status_code) = (xsd(-1),''); }
    when ("done")     { ($priority,$status_code) = (xsd(0),''); }
    when ("ok")       { ($priority,$status_code) = (xsd(0),xsd(0)); }
    when ("warning")  { ($priority,$status_code) = (xsd(0),xsd(1)); }
    when ("error")    { ($priority,$status_code) = (xsd(0),xsd(2)); }
    when ("fatal")    { ($priority,$status_code) = (xsd(0),xsd(3)); }
    default           { ($priority,$status_code) = ('?priority. FILTER (?priority >= 1)',''); }
  }

  $status_code = ' ?x build:status ?y. ?y build:what '.$status_code.'.' if $status_code;
  my $query = 'SELECT (count(distinct(?x)) as ?xCount) '
            . ' WHERE { ?x build:priority '.$priority.'. '.$status_code.' '.($conditions||'').' }';
  my $xml_ref = $self->sparql_query({query=>$query,repository=>$repository});
  ($xml_ref && $xml_ref->{results}->[0]->{result}->[0]->{binding}->{literal}->{content}) || 0;
}

sub get_entry_type {
  my ($self,$repository) = @_;
  my $query = 'SELECT ?y WHERE {?x build:entryType ?y .}';
  my $xml_ref = $self->sparql_query({query=>$query,repository=>$repository});
  $xml_ref->{results}->[0]->{result}->[0]->{binding}->{literal}->{content} || 'complex';
}

sub get_result_summary {
  my ($self,$repository,$severity,$category) = @_;
  my $result_summary = {};
  if (! $severity) {
    # Top-level summary, get all severities and their counts:
    my $types = [qw/ok warning error fatal/];
    $result_summary = { map { $_=> $self->count_entries($repository,$_)} @$types };
  } else {
    my $types_query = 'SELECT distinct ?z WHERE { ?x build:'.$severity.' ?y. ?y build:category ';
    if (! $category) {
      $types_query .= ' ?z. }';
    } else {
      $types_query .= ' '.xsd($category).'. ?y build:what ?z. }';
    }
    my $xml_ref = $self->sparql_query({query=>$types_query,repository=>$repository});
    my $bindings = ($xml_ref && $xml_ref->{results}->[0]->{result}) || [];
    my $types = [ map {$_->{binding}->{literal}->{content}} @$bindings ];

    # Get the counts for each of those
    foreach my $type(@$types) {
      my $count_conditions = undef;
      if (! $category) {
        $count_conditions = '?x build:'.$severity.' ?blank. ?blank build:category '.xsd($type);
      } else {
        $count_conditions = '?x build:'.$severity.' ?blank. ?blank build:category '.xsd($category).'. ?blank build:what '.xsd($type).'. ';
      }
      $result_summary->{sesame_unescape($type)} = $self->count_entries($repository,$severity,$count_conditions);
    }
  }
  # Only positive counts are relevant!
  foreach (keys %$result_summary) {
    delete $result_summary->{$_} unless ($result_summary->{$_}>0);
  }
  return $result_summary;
}

1;

__END__

=pod 

=head1 NAME

C<CorTeX::Backend::Sesame> - Sesame Triple Store API and driver

=head1 SYNOPSIS

    use CorTeX::Backend;
    # Class-tuning API
    $backend=CorTeX::Backend->new(exist_url=>$exist_url,verbosity=>0|1);
    $backend->sesame->method

=head1 DESCRIPTION

Low-level interaction with the Sesame triple store (via HTTP),
together with an API layer.

Provides an abstraction layer over the tedious low-level details.

=head2 METHODS

=over 4

=item C<< $backend->sesame->query($query,keep=>0|1); >>

Send a query to the Sesame backend.

=item C<< TODO: add all>>

=back

=head1 AUTHOR

Deyan Ginev <d.ginev@jacobs-university.de>

=head1 COPYRIGHT

 Research software, produced as part of work done by 
 the KWARC group at Jacobs University Bremen.
 Released under the GNU Public License

=cut
