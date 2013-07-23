# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | eXist XML Database Backend Connector                                | #
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
package CorTeX::Backend::SQLTaskAPI;
use strict;
use warnings;
use feature 'switch';
use Data::Dumper;
use CorTeX::Util::DB_File_Utils qw(db_file_connect db_file_disconnect);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(queue purge delete_corpus delete_service register_corpus register_service
  service_to_id corpus_to_id corpus_report id_to_corpus id_to_service count_entries
  current_corpora current_services service_report classic_report get_custom_entries
  get_result_summary service_description update_service

  repository_size mark_limbo_entries_queued get_entry_type);

our (%CorpusIDs,%ServiceIDs,%IDServices,%IDCorpora);
sub corpus_to_id {
  my ($db, $corpus) = @_;
  my $corpusid = $CorpusIDs{$corpus};
  if (! defined $corpusid) {
    my $sth=$db->prepare("SELECT corpusid from corpora where name=?");
    $sth->execute($corpus);
    ($corpusid) = $sth->fetchrow_array();
    $CorpusIDs{$corpus} = $corpusid; }
  return $corpusid; }
sub service_to_id {
  my ($db,$service) = @_;
  my $serviceid = $ServiceIDs{$service};
  if (! defined $serviceid) {
    my $sth=$db->prepare("SELECT serviceid from services where name=?");
    $sth->execute($service);
    ($serviceid) = $sth->fetchrow_array();
    $ServiceIDs{$service} = $serviceid; }
  return $serviceid; }
sub id_to_corpus {
  my ($db, $corpusid) = @_;
  my $corpus = $IDCorpora{$corpusid};
  if (! defined $corpus) {
    my $sth=$db->prepare("SELECT name from corpora where corpusid=?");
    $sth->execute($corpusid);
    ($corpus) = $sth->fetchrow_array(); }
  return $corpus; }
sub id_to_service {
  my ($db, $serviceid) = @_;
  my $service = $IDServices{$serviceid};
  if (! defined $service) {
    my $sth=$db->prepare("SELECT name from services where serviceid=?");
    $sth->execute($serviceid);
    ($service) = $sth->fetchrow_array();
    $IDServices{$serviceid} = $service; }
  return $service; }

sub delete_corpus {
  my ($db,$corpus) = @_;
  return unless ($corpus && (length($corpus)>0));
  my $corpusid = $db->corpus_to_id($corpus);
  return unless $corpusid; # Not present in the first place
  my $sth = $db->prepare("delete from corpora where corpusid=?");
  $sth->execute($corpusid);
  return $db->purge(corpusid=>$corpusid); }

sub delete_service {
  my ($db,$service) = @_;
  return unless ($service && (length($service)>0));
  my $serviceid = $db->service_to_id($service);
  my $sth = $db->prepare("delete from services where serviceid=?");
  $sth->execute($serviceid);
  return $db->purge(serviceid=>$service); }

sub register_corpus {
  my ($db,$corpus) = @_;
  return unless $corpus;
  my $sth = $db->prepare("INSERT INTO corpora (name) values(?)");
  $sth->execute($corpus);
  my $id = $db->last_inserted_id();
  $CorpusIDs{$corpus} = $id;
  return $id; }

sub register_service {
  my ($db,%service) = @_;
  my $message;
  # Prepare parameters
  foreach my $key(qw/name version id type/) { # Mandatory keys
    return (0,"Failed: Missing $key!") unless $service{$key}; }
  foreach my $key(qw/xpath url/) { # Optional keys
    $service{$key} //= '';}
  if ($service{url}) {
    # Register a new gearman URL
    my $dbhandle = db_file_connect;
    my @urls = split("\n", $dbhandle->{gearman_urls}||'');
    unless (grep {$_ eq $service{url}} @urls) {
      push @urls, $service{url}; }
    $dbhandle->{gearman_urls} = join("\n",@urls);
    db_file_disconnect($dbhandle); }
    
  # Register the Service
  # TODO: Check the name, version and iid are unique!
  my $sth = $db->prepare("INSERT INTO services (name,version,iid,type,xpath,url) values(?,?,?,?,?,?)");
  $message = $sth->execute(map {$service{$_}} qw/name version id type xpath url/);
  my $id = $db->last_inserted_id();
  $ServiceIDs{$service{name}} = $id;
  # Register Dependencies
  $sth = $db->prepare("INSERT INTO dependencies (master,foundation) values(?,?)");
  my $dependency_weight = 0;
  foreach my $foundation(@{$service{dependencies}}) {
    next if $foundation eq 'import'; # Built-in to always have completed prior to the service being registered
    $dependency_weight++;
    my $foundation_id = $db->service_to_id($foundation);
    $sth->execute($id,$foundation_id); }
  # Register Tasks on each corpus
  my $status = -5 - $dependency_weight;
  # For every import task, queue a task with the service $id
  # TODO: The list of tasks is proportional to the size of the corpus, so a big corpus will have millions of tasks
  #       how do we register them quickly? Maybe a single transaction will do the trick for the insert...
  #       but what about the enormous select? Do 3 million entries fit in memory?
  my $entry_query = $db->prepare("SELECT entry from tasks where corpusid=? and serviceid=1 and status=-1");
  my $insert_query = $db->prepare("INSERT into tasks (corpusid,serviceid,entry,status) values(?,?,?,?)");
  foreach my $corpus(@{$service{corpora}}) {
    my $corpusid = $db->corpus_to_id($corpus);
    $entry_query->execute($corpusid);
    my ($entry,@entries);
    $entry_query->bind_columns(\$entry);
    while ($entry_query->fetch) { push @entries, $entry; } 
    $db->do('BEGIN TRANSACTION');
    foreach my $e(@entries) {
      $insert_query->execute($corpusid,$id,$e,$status); }
    $db->do('COMMIT');
  }
  return $id; }

sub update_service {
  my ($db,%service) = @_;
  my $message;
  # Prepare parameters
  foreach my $key(qw/name version id oldname type/) { # Mandatory keys
    return (0,"Failed: Missing $key!") unless $service{$key}; }
  foreach my $key(qw/xpath url/) { # Optional keys
    $service{$key} //= '';}

  my $old_service = $db->service_description($service{oldname});
  # Register the Service
  # TODO: Check the name, version and iid are unique!
  my $sth = $db->prepare("UPDATE services SET name=?, version=?, iid=?, type=?, xpath=? ,url=?
    WHERE iid=?");
  $message = $sth->execute(map {$service{$_}} qw/name version id type xpath url oldid/);
  delete $ServiceIDs{$old_service->{name}};
  my $serviceid = $old_service->{serviceid};
  $ServiceIDs{$service{name}} = $serviceid;
  # TODO: Update Dependencies
  #$sth = $db->prepare("INSERT INTO dependencies (master,foundation) values(?,?)");
  my $dependency_weight = 0;
  foreach my $foundation(@{$service{dependencies}}) {
    next if $foundation eq 'import'; # Built-in to always have completed prior to the service being registered
    $dependency_weight++;
    my $foundation_id = $db->service_to_id($foundation);
    $sth->execute($serviceid,$foundation_id); }
  my $status = -5 - $dependency_weight;

  # Update URL
  if ($service{url} ne $old_service->{url}) {
    # Register a new gearman URL
    my $dbhandle = db_file_connect;
    my $urls = $dbhandle->{gearman_urls}||[];
    if ($old_service->{url}) {
      @$urls = grep {$_ ne $old_service->{url}} @$urls; }
    if ($service{url}) {
      @$urls = ((grep {$_ ne $service{url}} @$urls), $service{url}); }
    $dbhandle->{gearman_urls} = $urls;
    db_file_disconnect($dbhandle); }

  # Update Corpora
  my $select_active_corpora = 
    $db->prepare("select distinct(corpusid) from tasks where serviceid=?");
  $select_active_corpora->execute($serviceid);
  $old_service->{corpora}=[];
  while (my @row = $select_active_corpora->fetchrow_array()) {
    push @{$old_service->{corpora}}, @row; }
  $service{corpora} = [ map {$db->corpus_to_id($_)} @{$service{corpora}||[]} ];
  my ($delete,$add) = diff_arrays($old_service->{corpora},$service{corpora});
  # Delete old corpora
  my $delete_tasks_query = $db->prepare("DELETE from tasks where corpusid=? and serviceid=?");
  foreach my $corpusid(@$delete) {
    $delete_tasks_query->execute($corpusid,$serviceid); }
  # Takes care of rerunning all currently queued entries
  my $update_query = $db->prepare("UPDATE tasks SET status=? where serviceid=?");
  $update_query->execute($status,$serviceid);
  # Add new corpora
  my $entry_query = $db->prepare("SELECT entry from tasks where corpusid=? and serviceid=1 and status=-1");
  my $insert_query = $db->prepare("INSERT into tasks (corpusid,serviceid,entry,status) values(?,?,?,?)");
  foreach my $corpusid(@$add) {
    $entry_query->execute($corpusid);
    my ($entry,@entries);
    $entry_query->bind_columns(\$entry);
    while ($entry_query->fetch) { push @entries, $entry; } 
    $db->do('BEGIN TRANSACTION');
    foreach my $e(@entries) {
      $insert_query->execute($corpusid,$serviceid,$e,$status); }
    $db->do('COMMIT'); }
  return $serviceid; }

sub diff_arrays {
  my ($old_array,$new_array) = @_;
  $old_array //= [];
  $new_array //= [];
  my $delete=[];
  my $add = [@$new_array];
  while (@$old_array) {
    my $element = shift @$old_array;
    my @filtered_new = grep {$_ ne $element} @$add;
    if (scalar(@filtered_new) == scalar(@$add)) {
      # Not found, delete $element
      push @$delete, $element;
    } else {
      # Found, next
      $add = \@filtered_new;
    }}
  return ($delete,$add); }

sub current_corpora {
  my ($db) = @_;
  my $corpora = [];
  my $sth = $db->prepare("select name from corpora");
  $sth->execute;
  while (my @row = $sth->fetchrow_array())
  {
    push @$corpora, @row;
  }
  $sth->finish();
  return $corpora; }

sub current_services {
  my ($db) = @_;
  my $services = [];
  my $sth = $db->prepare("select name from services");
  $sth->execute;
  while (my @row = $sth->fetchrow_array())
  {
    push @$services, @row;
  }
  $sth->finish();
  return $services; }

sub service_description {
  my ($db,$name) = @_;
  my $sth = $db->prepare("select * from services where name=?");
  $sth->execute($name);
  my $description = $sth->fetchrow_hashref;
  return $description;
}

sub queue {
  my ($db,%options) = @_;
  my $corpus = $options{corpus};
  my $service = $options{service};
  $options{corpusid} = $db->corpus_to_id($corpus);
  $options{serviceid} = $db->service_to_id($service);
  # Note: The two "status" lookups are not a typo, we need both to have the "on duplicate" clause set:
  if (lc($db->{sqldbms}) eq 'mysql') {
    my @fields = grep {defined && (length($_)>0)} map {$options{$_}}
       qw/corpusid entry serviceid status status/;
    return unless scalar(@fields) == 5; # Exactly 5 data points to queue
    my $sth = $db->prepare("INSERT INTO tasks (corpusid,entry,serviceid,status) VALUES (?,?,?,?) 
      ON DUPLICATE KEY UPDATE status=?;");
    $sth->execute(@fields);
  } else {
    my @fields = grep {defined && (length($_)>0)} map {$options{$_}} qw/corpusid entry serviceid status/;
    return unless scalar(@fields) == 4; # Exactly 4 data points to queue
    my $sth = $db->prepare("INSERT OR REPLACE INTO tasks (corpusid,entry,serviceid,status) VALUES (?,?,?,?)");
    $sth->execute(@fields);
  }
  return 1; }

sub purge {
  my ($db,%options) = @_;
  my $entry = $options{entry} ? "entry=?" : "";
  $options{corpusid} //= $options{corpus} && $db->corpus_to_id($options{corpus});
  $options{serviceid} //= $options{service} && $db->service_to_id($options{service});
  my $corpus = $options{corpusid} ? "corpusid=?" : "";
  my $service = $options{serviceid} ? "serviceid=?" : "";
  my $status = $options{status} ? "status=?" : "";
  my @fields = grep {length($_)>0} ($entry,$corpus,$service,$status);
  return unless @fields;
  my $where_clause = join(" AND ",@fields);
  my $sth = $db->prepare("DELETE FROM tasks WHERE ".$where_clause.";");
  $sth->execute(grep {defined} map {$options{$_}} qw/entry corpusid serviceid status/);
  return 1; }


# HIGH Level API

sub corpus_report {
  my ($db,$corpus_name)=@_;
  return unless $corpus_name;
  my $corpusid = $db->corpus_to_id($corpus_name);
  return unless $corpusid;
  my $sth = $db->prepare("SELECT serviceid, count(entry), status FROM tasks
   where corpusid=?
   group by serviceid, status");
  $sth->execute($corpusid);
  my %report=();
  my ($serviceid,$count,$status);
  $sth->bind_columns(\($serviceid,$count,$status));
  my $alive = 0; 
  while ($sth->fetch) {
    # Representing an HTML table row:
    $report{$serviceid}{status_decode($status)} += $count;
    $alive = 1 if (!($alive || $status)); }
  # Decode the keys
  my $readable_report = {};
  foreach my $id(keys %report) {
    my $service = $db->id_to_service($id);
    my $service_report = $report{$id};
    $readable_report->{$service} = $service_report; }

  return ($readable_report,$alive); }

sub service_report {
  my ($db,$service_name)=@_;
  return unless $service_name;
  my $serviceid = $db->service_to_id($service_name);
  return unless $serviceid;
  my $sth = $db->prepare("SELECT corpusid, count(entry), status FROM tasks
   where serviceid=?
   group by corpusid, status");
  $sth->execute($serviceid);
  my %report=();
  my ($corpusid,$count,$status);
  $sth->bind_columns(\($corpusid,$count,$status));
  my $alive = 0; 
  while ($sth->fetch) {
    # Representing an HTML table row:
    $report{$corpusid}{status_decode($status)} += $count;
    $alive = 1 if (!($alive || $status)); }
  # Decode the keys
  my $readable_report = {};
  foreach my $id(keys %report) {
    my $corpus = $db->id_to_corpus($id);
    my $corpus_report = $report{$id};
    $readable_report->{$corpus} = $corpus_report; }

  return ($readable_report,$alive); }

sub classic_report { # Report in detail on a <corpus,service> pair 
  my ($db,$corpus_name,$service_name) = @_;
  return unless $corpus_name && $service_name;
  my $serviceid = $db->service_to_id($service_name);
  my $corpusid = $db->corpus_to_id($corpus_name);
  return unless $serviceid && $corpusid;
  my $sth = $db->prepare("SELECT status,count(entry) from tasks
   where corpusid=? and serviceid=?
   group by status");

  $sth->execute($corpusid,$serviceid);
  return 1; }

sub count_entries {
  my ($db,%options)=@_;
  my $corpus_name = $options{corpus};
  my $service_name = $options{service};
  my $select = $options{select};
  return unless $corpus_name || $service_name;
  my $corpusid = $db->corpus_to_id($corpus_name) if $corpus_name;
  my $serviceid = $db->service_to_id($service_name) if $service_name;
  return unless $corpusid || $serviceid;
  if (!$select && ($corpusid && $serviceid)) {
    my $sth = $db->prepare("SELECT status, count(entry) FROM tasks 
      where corpusid=? and serviceid=?
      group by status");
    $sth->execute($corpusid,$serviceid);
    my ($count,$status,%report);
    $sth->bind_columns(\($status,$count));
    while ($sth->fetch) {
      $report{status_decode($status)} += $count;
    }
    return \%report; }
  elsif ($select eq 'all') {
    $serviceid //= 1;
    my $sth = $db->prepare("SELECT count(entry) FROM tasks where corpusid=? and serviceid=?");
    $sth->execute($corpusid,$serviceid);
    my $total;
    $sth->bind_columns(\$total);
    $sth->fetch;
    return $total; }
  else {
    $select = status_decode($select);
    return unless $select =~ /^(\d\-\<\>\=)+$/; # make sure the selector is safe
    my $sth = $db->prepare("SELECT count(entry) FROM tasks where corpusid=? and serviceid=? and status".$select);
    $sth->execute($corpusid,$serviceid);
    my $value;
    $sth->bind_columns(\$value);
    $sth->fetch;
    return $value;
    }}

sub get_custom_entries {
  my ($db,$options) = @_;
  print STDERR Dumper($options);
  my $corpusid = $db->corpus_to_id($options->{corpus});
  my $serviceid = $db->service_to_id($options->{service});
  $options->{select} //= $options->{severity};
  my $status = status_encode($options->{select});
  my $sth = $db->prepare("SELECT entry from tasks where corpusid=? and serviceid=? and status".$status
            . " ORDER BY entry \n"
            . ($options->{limit} ? "LIMIT ".$options->{limit}." \n" : '')
            . ($options->{from} ? "OFFSET ".$options->{from}." \n" : ''));
  $sth->execute($corpusid,$serviceid);
  my @entries;
  print STDERR "STATUS: $status\n";
  if ($options->{select} && $options->{category} && $options->{what}) {
    # Return pairs of results and related details message
    # TODO: Make sure this is always in the right order, not sure how reliably XML::Simple parses it 
    # @entries = map {[$name, $content, $url] }
  } else {
    # Only return results
    #@entries = [$name, undef, $url ]
    my $name;
    $sth->bind_columns(\$name);
    while ($sth->fetch) {
      print STDERR "NAME: $name ;\n\n";
      push @entries, [$name,undef,undef]; 
    }
  }
  #print STDERR Dumper(@entries);
  \@entries; }

sub get_result_summary {
 my ($db,%options) = @_; 
 my $result_summary = {};
 $options{select} //= $options{severity};
  if (! $options{severity}) {
    # Top-level summary, get all severities and their counts:
    $result_summary = $db->count_entries(%options);
  } else {
    # my $types_query = 'SELECT distinct ?z WHERE { ?x build:'.$severity.' ?y. ?y build:category ';
    # if (! $category) {
    #   $types_query .= ' ?z. }';
    # } else {
    #   $types_query .= ' '.xsd($category).'. ?y build:what ?z. }';
    # }
    # my $xml_ref = $self->sparql_query({query=>$types_query,repository=>$repository});
    # my $bindings = ($xml_ref && $xml_ref->{results}->[0]->{result}) || [];
    # my $types = [ map {$_->{binding}->{literal}->{content}} @$bindings ];

    # # Get the counts for each of those
    # foreach my $type(@$types) {
    #   my $count_conditions = undef;
    #   if (! $category) {
    #     $count_conditions = '?x build:'.$severity.' ?blank. ?blank build:category '.xsd($type);
    #   } else {
    #     $count_conditions = '?x build:'.$severity.' ?blank. ?blank build:category '.xsd($category).'. ?blank build:what '.xsd($type).'. ';
    #   }
    #   $result_summary->{sesame_unescape($type)} = 
    #   $self->count_entries(
    #     %options
    #     select=>$count_conditions);
    # }
  }
  # Only positive counts are relevant!
  foreach (keys %$result_summary) {
    delete $result_summary->{$_} unless ($result_summary->{$_}>0);
  }
  return $result_summary;
}

sub status_decode {
  my ($status_code) = @_;
  given ($status_code) {
    when (-1) {return 'ok'}
    when (-2) {return 'warning'}
    when (-3) {return 'error'}
    when (-4) {return 'fatal'}
    when (-5) {return 'queued'}
    default {
      if ($status_code > 0) {
        return 'processing'
      } else {
        return 'blocked'
      }
    }
  };}

sub status_encode {
  my ($status) = @_;
  given ($status) {
    when ('ok') {return '=-1'}
    when ('warning') { return '=-2'}
    when ('error') {return '=-3'}
    when ('fatal') {return '=-4'}
    when ('queued') {return '=-5'}
    when ('processing') {return '>0'}
    when ('blocked') {return '<-5'}
    default {return;}}}

  1;


sub repository_size {
 return 1; # TODO
}

sub mark_limbo_entries_queued {
  return 1; # TODO
}

sub get_entry_type {
  return 'simple';
}

  __END__