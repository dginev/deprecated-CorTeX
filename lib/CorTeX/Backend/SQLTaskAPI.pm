# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | TaskDB API for SQL Backends                                         | #
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
use CorTeX::Util::Compare qw(set_difference);
use CorTeX::Util::Data qw(parse_log);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(queue purge delete_corpus delete_service register_corpus register_service
  service_to_id serviceid_to_iid corpus_to_id corpus_report id_to_corpus id_to_service serviceiid_to_formats
  count_entries count_messages
  current_corpora current_services current_inputformats current_outputformats
  service_report classic_report get_custom_entries
  get_result_summary service_description update_service mark_custom_entries_queued
  mark_entry_queued

  repository_size mark_limbo_entries_queued get_entry_type
  fetch_tasks complete_tasks);

our (%CorpusIDs,%ServiceIDs,%IDServices,%IDCorpora,%ServiceFormats);
our (%IIDs);
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
sub serviceiid_to_formats {
  my ($db,$serviceiid) = @_;
  my $service_formats = $ServiceFormats{$serviceiid};
  if (! defined $service_formats) {
    my $sth = $db->prepare("SELECT inputformat, outputformat, inputconverter from services where iid=?");
    $sth->execute($serviceiid);
    $service_formats = [ $sth->fetchrow_array() ];
    $ServiceFormats{$serviceiid} = $service_formats; }
  return $service_formats; }
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
sub serviceid_to_iid {
  my ($db, $serviceid) = @_;
  my $iid = $IIDs{$serviceid};
  if (! defined $iid) {
    my $sth=$db->prepare("SELECT iid from services where serviceid=?");
    $sth->execute($serviceid);
    ($iid) = $sth->fetchrow_array();
    $IIDs{$serviceid} = $iid; }
  return $iid; }

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
  $service{inputformat} = lc($service{inputformat});
  $service{outputformat} = lc($service{outputformat});
  $service{requires_analyses} //= [];
  $service{requires_aggregation} //= [];
  my $sth = $db->prepare("INSERT INTO services 
      (name,version,iid,type,xpath,url,inputconverter,inputformat,outputformat,resource) 
      values(?,?,?,?,?,?,?,?,?,?)");
  $message = $sth->execute(map {$service{$_}} qw/name version id type xpath url inputconverter inputformat outputformat resource/);
  my $id = $db->last_inserted_id();
  $ServiceIDs{$service{name}} = $id;
  $ServiceFormats{$service{name}} = [$service{inputformat},$service{outputformat}];
  # Register Dependencies
  $sth = $db->prepare("INSERT INTO dependencies (master,foundation) values(?,?)");
  my $dependency_weight = 0;
  my @dependencies = grep {defined} ($service{inputconverter},@{$service{requires_analyses}},@{$service{requires_aggregation}});
  foreach my $foundation(@dependencies) {
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
  my $major_change = 0;
  if (($old_service->{name} ne $service{name}) || 
      ($old_service->{version} ne $service{version}) ||
      ($old_service->{inputconverter} ne $service{inputconverter}) ||
      ($old_service->{inputformat} ne $service{inputformat}) ||
      ($old_service->{outputformat} ne $service{outputformat})
    ) {
    $major_change = 1; }
  # Register the Service
  # TODO: Check the name, version and iid are unique!
  my $sth = $db->prepare("UPDATE services SET name=?, version=?, iid=?, type=?, xpath=?,
                          url=?, inputconverter=?, inputformat=?, outputformat=?, resource=?
                          WHERE iid=?");
  $message = $sth->execute(map {$service{$_}} 
    qw/name version id type xpath url inputconverter inputformat outputformat resource oldid/);
  delete $ServiceIDs{$old_service->{name}};
  my $serviceid = $old_service->{serviceid};
  $ServiceIDs{$service{name}} = $serviceid;
  $ServiceFormats{$service{name}} = [$service{inputformat},$service{outputformat}];
  # TODO: Update Dependencies
  $sth = $db->prepare("INSERT INTO dependencies (master,foundation) values(?,?)");
  my $dependency_weight = 0;
  my @dependencies = ($service{inputconverter},@{$service{requires_analyses}},@{$service{requires_aggregation}});
  foreach my $foundation(@dependencies) {
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
  my ($delete,$add) = set_difference($old_service->{corpora},$service{corpora});
  # Delete old corpora
  my $delete_tasks_query = $db->prepare("DELETE from tasks where corpusid=? and serviceid=?");
  foreach my $corpusid(@$delete) {
    $delete_tasks_query->execute($corpusid,$serviceid); }
  # Takes care of rerunning all currently queued entries IFF there was a change apart from the corpus change
  if ($major_change) {
    my $update_query = $db->prepare("UPDATE tasks SET status=? where serviceid=?");
    $update_query->execute($status,$serviceid); }
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

sub current_corpora {
  my ($db) = @_;
  my $corpora = [];
  my $sth = $db->prepare("select name from corpora");
  $sth->execute;
  while (my @row = $sth->fetchrow_array()) {
    push @$corpora, @row; }
  $sth->finish();
  return $corpora; }

sub current_services {
  my ($db) = @_;
  my $services = {1=>[],2=>[],3=>[]};
  my $sth = $db->prepare("select name,type from services");
  $sth->execute;
  my ($name,$type);
  $sth->bind_columns(\($name,$type));
  while ($sth->fetch) {
    push @{$services->{$type}}, $name; }
  $sth->finish();
  return $services; }

sub current_inputformats {
  my ($db) = @_;
  my $inputformats = [];
  my $sth = $db->prepare("select distinct(inputformat) from services");
  $sth->execute;
  while (my @row = $sth->fetchrow_array()) {
    push @$inputformats, @row; }
  $sth->finish();
  return $inputformats; }

sub current_outputformats {
  my ($db) = @_;
  my $outputformats = [];
  my $sth = $db->prepare("select distinct(outputformat) from services");
  $sth->execute;
  while (my @row = $sth->fetchrow_array())
  {
    push @$outputformats, @row;
  }
  $sth->finish();
  return $outputformats; }

sub service_description {
  my ($db,$name) = @_;
  my $sth = $db->prepare("select * from services where name=?");
  $sth->execute($name);
  my $description = $sth->fetchrow_hashref;
  # Collect list of corpora on which service is enabled:
  return {} unless $description->{serviceid};
  $sth = $db->prepare("select distinct(corpusid) from tasks where serviceid=?");
  $sth->execute($description->{serviceid});
  my @corpora; 
  my $corpusid;
  $sth->bind_columns(\$corpusid);
  while ($sth->fetch) {
      push @corpora, $db->id_to_corpus($corpusid); }
  $description->{corpora} = \@corpora;
  return $description; }

sub mark_entry_queued {
  my ($db,$data) = @_;
  return unless ($data->{corpus} && $data->{service} && $data->{entry});
  my $corpusid = $db->corpus_to_id($data->{corpus});
  my $serviceid = $db->service_to_id($data->{service});
  my $queue_entry_query = $db->prepare("UPDATE tasks SET status=-5 
      WHERE corpusid=? AND serviceid=? and entry=?");
  my $delete_messages_query = $db->prepare("DELETE from logs WHERE taskid IN
     (SELECT logs.taskid FROM logs INNER JOIN tasks ON (tasks.taskid = logs.taskid)
      WHERE tasks.status=-5)");
  $queue_entry_query->execute($corpusid,$serviceid,$data->{entry});
  $delete_messages_query->execute();
  # TODO: Also handle dependencies: +1 on any service depending on serviceid, for this entry
  return 1;
}

sub mark_custom_entries_queued {
  my ($db,$data) = @_;
  # Return unless we know which corpus and service we're dealing with (TODO: Raise some error)
  return unless (($data->{corpus} || $data->{corpusid}) && ($data->{service} || $data->{serviceid}));
  $data->{corpusid} //= $db->corpus_to_id($data->{corpus});
  $data->{serviceid} //= $db->service_to_id($data->{service});
  my ($corpusid,$serviceid) = map {$data->{$_}} qw/corpusid serviceid/;
  return unless $corpusid && $serviceid; # TODO: Raise error
  # Prepare query components for the customizable fragments - severity, category and what.
  my ($severity,$category,$what)=(q{},q{},q{});
  if ($data->{severity}) {
    $severity = status_encode($data->{severity});
    if ($data->{category}) {
      $category = $data->{category};
      if ($data->{what}) {
        $what = $data->{what};
      }}}

  my $rerun_query;
  # Start a transaction
  $db->do("BEGIN TRANSACTION");
  if ($what) { # We have severity, category and what
    # TODO: Propagate blocks to all (service,entry) pairs depending on this task
    # Mark for rerun = SET the status to all affected tasks to -5
    $rerun_query = $db->prepare("UPDATE tasks SET status=-5 
      WHERE taskid IN (SELECT tasks.taskid FROM tasks INNER JOIN logs ON (tasks.taskid = logs.taskid)
      WHERE tasks.corpusid=? AND tasks.serviceid=? AND tasks.status$severity
      AND logs.category=? and logs.what=?)");
    $rerun_query->execute($corpusid,$serviceid,$category,$what); }
  elsif ($category) { # We have severity and category
    # TODO: Propagate blocks to all (service,entry) pairs depending on this task
    # Mark for rerun = SET the status to all affected tasks to -5
    $rerun_query = $db->prepare("UPDATE tasks SET status=-5 
      WHERE taskid IN (SELECT tasks.taskid FROM tasks INNER JOIN logs ON (tasks.taskid = logs.taskid)
      WHERE tasks.corpusid=? AND tasks.serviceid=? AND tasks.status$severity
      AND logs.category=?)");
    $rerun_query->execute($corpusid,$serviceid,$category); }
  elsif ($severity) { # We have severity
    # TODO: Propagate blocks to all (service,entry) pairs depending on this task
    # Mark for rerun = SET the status to all affected tasks to -5
    $rerun_query = $db->prepare("UPDATE tasks SET status=-5 
      WHERE corpusid=? AND serviceid=? AND status$severity");
    $rerun_query->execute($corpusid,$serviceid); }
  else { #Simplest case, rerun an entire (corpus,service) pair.
    #Mark for rerun = SET the status to all affected tasks to -5
    $rerun_query = $db->prepare("UPDATE tasks SET status=-5 
      WHERE corpusid=? AND serviceid=?");
    $rerun_query->execute($corpusid,$serviceid);    
    # TODO: Propagate blocks to all (service,entry) pairs depending on this task
  }
  #Delete all existing messages for tasks that are marked for rerun (status=-5)

  my $delete_messages_query = $db->prepare("DELETE from logs WHERE taskid IN
     (SELECT logs.taskid FROM logs INNER JOIN tasks ON (tasks.taskid = logs.taskid)
      WHERE tasks.status=-5)");
  $delete_messages_query->execute();
  $db->do("COMMIT");
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
  while ($sth->fetch) {
    # Representing an HTML table row:
    $report{$serviceid}{status_decode($status)} += $count; }
  # Decode the keys
  my $readable_report = {};
  foreach my $id(keys %report) {
    my $service = $db->id_to_service($id);
    my $service_report = $report{$id};
    $readable_report->{$service} = $service_report; }

  return $readable_report; }

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
  while ($sth->fetch) {
    # Representing an HTML table row:
    $report{$corpusid}{status_decode($status)} += $count; }
  # Decode the keys
  my $readable_report = {};
  foreach my $id(keys %report) {
    my $corpus = $db->id_to_corpus($id);
    my $corpus_report = $report{$id};
    $readable_report->{$corpus} = $corpus_report; }

  return ($readable_report); }

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
  $options{corpusid} //= $db->corpus_to_id($options{corpus}) if $options{corpus};
  $options{serviceid} //= $db->service_to_id($options{service}) if $options{service};
  my $corpusid = $options{corpusid};
  my $serviceid = $options{serviceid};
  my $select = $options{select};
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

sub count_messages {
  my ($db,%options)=@_;
  $options{corpusid} //= $db->corpus_to_id($options{corpus});
  $options{serviceid} //= $db->service_to_id($options{service});
  my $corpusid = $options{corpusid};
  my $serviceid = $options{serviceid};
  my $select = $options{select};
  return unless $corpusid || $serviceid;
  if (!$select && ($corpusid && $serviceid)) {
    my $sth = $db->prepare("SELECT severity, count(messageid) 
      FROM logs INNER JOIN tasks ON (tasks.taskid = logs.taskid)
      WHERE corpusid=? and serviceid=?
      group by severity");
    $sth->execute($corpusid,$serviceid);
    my ($count,$status,%report);
    $sth->bind_columns(\($status,$count));
    while ($sth->fetch) {
      $report{status_decode($status)} += $count;
    }
    return \%report; }
  elsif ($select eq 'all') {
    $serviceid //= 1;
    my $sth = $db->prepare("SELECT count(messageid) 
      FROM logs INNER JOIN tasks ON (tasks.taskid = logs.taskid)
      WHERE corpusid=? and serviceid=?");
    $sth->execute($corpusid,$serviceid);
    my $total;
    $sth->bind_columns(\$total);
    $sth->fetch;
    return $total; }
  else {
    $select = status_decode($select);
    return unless $select =~ /^(\d\-\<\>\=)+$/; # make sure the selector is safe
    my $sth = $db->prepare("SELECT count(messageid) 
      FROM logs INNER JOIN tasks ON (tasks.taskid = logs.taskid)
      WHERE corpusid=? and serviceid=? and status".$select);
    $sth->execute($corpusid,$serviceid);
    my $value;
    $sth->bind_columns(\$value);
    $sth->fetch;
    return $value;
    }}

sub get_custom_entries {
  my ($db,$options) = @_;
  $options->{corpusid} //= $db->corpus_to_id($options->{corpus});
  $options->{serviceid} //= $db->service_to_id($options->{service});
  my $corpusid = $options->{corpusid};
  my $serviceid = $options->{serviceid};
  $options->{select} //= $options->{severity};
  my @entries;
  if ($options->{select} && $options->{category} && $options->{what}) {
    # Return pairs of results and related details message
    my $severity = status_code($options->{select});
    my $sth = $db->prepare("SELECT entry, details from "
      . " tasks INNER JOIN logs ON (tasks.taskid = logs.taskid) "
      . " WHERE tasks.corpusid=? and tasks.serviceid=? and logs.severity=$severity "
      . " and logs.category=? and logs.what=? "
      . " ORDER BY entry \n"
      . ($options->{limit} ? "LIMIT ".$options->{limit}." \n" : '')
      . ($options->{from} ? "OFFSET ".$options->{from}." \n" : ''));
    $sth->execute($corpusid,$serviceid,$options->{category},$options->{what});
    my ($entry, $details);
    $sth->bind_columns(\($entry,$details));
    while ($sth->fetch) {
      push @entries, [$entry,$details,undef];
      # @entries = map {[$name, $content, $url] }
    }}
  else {
    # Only return results if OK (TODO: URL?)
    my $status = status_encode($options->{select});
    my $sth = $db->prepare("SELECT entry from tasks where corpusid=? and serviceid=? and status".$status
      . " ORDER BY entry \n"
      . ($options->{limit} ? "LIMIT ".$options->{limit}." \n" : '')
      . ($options->{from} ? "OFFSET ".$options->{from}." \n" : ''));
    $sth->execute($corpusid,$serviceid);
    #@entries = [$name, undef, $url ]
    my $name;
    $sth->bind_columns(\$name);
    while ($sth->fetch) {
      push @entries, [$name,"OK",undef]; 
    }}
  #print STDERR Dumper(@entries);
  \@entries; }

sub get_result_summary {
 my ($db,%options) = @_; 
 my $result_summary = {};
 return unless $options{corpus} && $options{service};
 my $corpusid = $db->corpus_to_id($options{corpus});
 my $serviceid = $db->service_to_id($options{service});
 my $count_clause = ($options{countby} eq 'message') ? 'messageid' : 'distinct(tasks.taskid)';
  if (! $options{severity}) {
    # Top-level summary, get all severities and their counts:
    if ($options{countby} eq 'message') {
      $result_summary = $db->count_messages(%options); }
    else {
      $result_summary = $db->count_entries(%options); }}
  elsif (! $options{category}) {
    $options{severity} = status_code($options{severity});
    my $types_query = $db->prepare("SELECT distinct(category),count($count_clause) 
      FROM logs INNER JOIN tasks ON (tasks.taskid = logs.taskid)
      WHERE corpusid=? AND serviceid=? AND severity=?
      group by category");
    $types_query->execute($corpusid,$serviceid,$options{severity});
    my ($category,$count);
    $types_query->bind_columns( \($category,$count));
    while ($types_query->fetch) {
      $result_summary->{$category} = $count if $count>0;
    }}
  else {
    # We have both severity and category, query for "what" component
    $options{severity} = status_code($options{severity});
    my $types_query = $db->prepare("SELECT distinct(what),count($count_clause) 
      FROM logs INNER JOIN tasks ON (tasks.taskid = logs.taskid)
      WHERE corpusid=? AND serviceid=? AND severity=? AND category=?
      group by what");
    $types_query->execute($corpusid,$serviceid,$options{severity},$options{category});
    my ($what,$count);
    $types_query->bind_columns( \($what,$count));
    while ($types_query->fetch) {
      $result_summary->{$what} = $count if $count>0;
    }}
  return $result_summary; }

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

sub status_code {
  my ($status) = @_;
  given ($status) {
    when ('ok') {return '-1'}
    when ('warning') { return '-2'}
    when ('error') {return '-3'}
    when ('fatal') {return '-4'}
    when ('queued') {return '-5'}
    when ('processing') {return '1'}
    when ('blocked') {return '-6'}
    default {return;}}}


  1;


sub repository_size {
 return 1; # TODO
}

sub mark_limbo_entries_queued {
  my ($db) = @_;
  # Entries in limbo have already had their follow-up services blocked 
  # AMD their messages erased, so all we need to do is make them available for processing again
  my $sth = $db->prepare("UPDATE tasks SET status=-5 WHERE status>0");
  $sth->execute();
}

sub get_entry_type {
  return 'simple';
}

sub fetch_tasks {
  my ($db,%options) = @_;
  my $size = $options{size};
  my $mark = int(1+rand(10000));
  my $sth = $db->prepare("UPDATE tasks SET status=? WHERE status=-5 LIMIT ?");
  $sth->execute($mark,$size);
  $sth = $db->prepare("SELECT taskid,serviceid,entry from tasks where status=?");
  $sth->execute($mark);
  my (%row,@tasks);
  $sth->bind_columns( \( @row{ @{$sth->{NAME_lc} } } ));
  while ($sth->fetch) {
    # Name of the function:
    $row{iid}=$db->serviceid_to_iid($row{serviceid});
    push @tasks, {%row};
  }
  return($mark,\@tasks); }

sub complete_tasks {
  my ($db,$results) = @_;
  return unless @$results;
  my $mark_complete = $db->prepare("UPDATE tasks SET status=? WHERE taskid=?");
  my $delete_messages = $db->prepare("DELETE from logs where taskid=?");
  my $add_message = $db->prepare("INSERT INTO logs (taskid, severity, category, what, details) values(?,?,?,?,?)");
  # TODO: Decrease the requirements on any blocked jobs by this service, for this entry.

  # Insert in TaskDB
  $db->do('BEGIN TRANSACTION');
  foreach my $result(@$results) {
    my $taskid = $result->{taskid};
    $delete_messages->execute($taskid);
    $mark_complete->execute($result->{status},$taskid);
    foreach my $message (@{$result->{messages}||[]}) {
      $message->{severity} = status_code($message->{severity});
      $add_message->execute($taskid,map {$message->{$_}} qw/severity category what details/);
    }
  }
  $db->do('COMMIT');
}

1;
__END__