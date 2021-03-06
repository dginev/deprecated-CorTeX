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
use Data::Dumper;

use CorTeX::Util::DB_File_Utils qw(db_file_connect db_file_disconnect);
use CorTeX::Util::Compare qw(set_difference);
use CorTeX::Util::Data qw(parse_log);
use CorTeX::Util::Gearman qw(available_workers);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(queue purge delete_corpus delete_service register_corpus register_service
  service_to_id serviceid_to_iid corpus_to_id corpus_report id_to_corpus id_to_service
  serviceiid_to_id serviceid_enables serviceid_requires
  count_entries count_messages
  current_corpora current_services current_inputformats current_outputformats
  service_report classic_report get_custom_entries
  get_result_summary service_description update_service mark_custom_entries_queued
  mark_entry_queued mark_rerun_blocked
  task_report
  repository_size mark_limbo_entries_queued
  fetch_tasks complete_tasks);

our (%CorpusIDs,%ServiceIDs,%IDServices,%IDCorpora,%ServiceDescriptions); # Maps between internal and external names
our (%IIDs,%IID_to_ID); # More maps
our (%ServiceIDEnables,%ServiceIDRequires); # Dependencies

sub corpus_to_id {
  my ($db, $corpus) = @_;
  my $corpusid = $CorpusIDs{$corpus};
  if (! defined $corpusid) {
    my $sth=$db->prepare("SELECT corpusid from corpora where name=?");
    $sth->execute($corpus);
    $sth->bind_columns(\$corpusid);
    $sth->fetch;
    $CorpusIDs{$corpus} = $corpusid; }
  return $corpusid; }
sub service_to_id {
  my ($db,$service) = @_;
  my $serviceid = $ServiceIDs{$service};
  if (! defined $serviceid) {
    my $sth=$db->prepare("SELECT serviceid from services where name=?");
    $sth->execute($service);
    $sth->bind_columns(\$serviceid);
    $sth->fetch;
    $ServiceIDs{$service} = $serviceid; }
  return $serviceid; }
sub serviceid_enables {
  my ($db,$serviceid) = @_;
  my $enabled_services = $ServiceIDEnables{$serviceid};
  if (! defined $enabled_services) {
    $enabled_services = [];
    my $sth = $db->prepare("SELECT master from dependencies where foundation=?");
    $sth->execute($serviceid);
    my $master_service;
    $sth->bind_columns(\$master_service);
    while ($sth->fetch) {
      push @$enabled_services, $master_service;
    }
    $ServiceIDEnables{$serviceid} = $enabled_services;
  }
  return @$enabled_services; }
sub serviceid_requires {
  my ($db,$serviceid) = @_;
  my $required_services = $ServiceIDRequires{$serviceid};
  if (! defined $required_services) {
    $required_services = [];
    my $sth = $db->prepare("SELECT foundation from dependencies where master=?");
    $sth->execute($serviceid);
    my $foundation_service;
    $sth->bind_columns(\$foundation_service);
    while ($sth->fetch) {
      push @$required_services, $foundation_service;
    }
    $ServiceIDRequires{$serviceid} = $required_services;
  }
  return @$required_services; }
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
  my $iid = $IIDs{"$serviceid"};
  if (! defined $iid) {
    my $sth=$db->prepare("SELECT iid from services where serviceid=?");
    $sth->execute($serviceid);
    ($iid) = $sth->fetchrow_array();
    $IIDs{"$serviceid"} = $iid; }
  return $iid; }
sub serviceiid_to_id {
  my ($db, $serviceiid) = @_;
  my $id = $IID_to_ID{$serviceiid};
  if (! defined $id) {
    my $sth=$db->prepare("SELECT serviceid from services where iid=?");
    $sth->execute($serviceiid);
    ($id) = $sth->fetchrow_array();
    $IID_to_ID{$serviceiid} = $id; }
  return $id; }

sub delete_corpus {
  my ($db,$corpus) = @_;
  return unless ($corpus && (length($corpus)>0));
  my $corpusid = $db->corpus_to_id($corpus);
  return unless $corpusid; # Not present in the first place
  my $sth = $db->prepare("delete from corpora where corpusid=?");
  $sth->execute($corpusid);
  return $db->purge(corpusid=>$corpusid); }

# TODO: We don't have a good deleting workflow for now
# sub delete_service {
#   my ($db,$service) = @_;
#   return unless ($service && (length($service)>0));
#   my $serviceid = $db->service_to_id($service);
#   my $sth = $db->prepare("delete from services where serviceid=?");
#   $sth->execute($serviceid);
#   return $db->purge(serviceid=>$service); }

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
  foreach my $key(qw/name version iid type/) { # Mandatory keys
    return (0,"Failed: Missing $key!") unless defined $service{$key}; }
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
  $service{'entry-setup'} //= 0; # Default is simple
  $service{requires_analyses} //= [];
  $service{requires_aggregation} //= [];
  $db->do($db->{begin_transaction});
  my $sth = $db->prepare("INSERT INTO services 
      (name,version,iid,type,xpath,url,inputconverter,inputformat,outputformat,resource,entrysetup) 
      values(?,?,?,?,?,?,?,?,?,?,?)");
  $message = $sth->execute(map {$service{$_}} qw/name version iid type xpath url inputconverter inputformat outputformat resource entry-setup/);
  my $id = $db->last_inserted_id();
  $ServiceIDs{$service{name}} = $id;
  $ServiceDescriptions{$service{name}} = {%service};
  # Register Dependencies
  $sth = $db->prepare("INSERT INTO dependencies (master,foundation) values(?,?)");
  my $dependency_weight = 0;
  my @dependencies = grep {defined} ($service{inputconverter},@{$service{requires_analyses}},@{$service{requires_aggregation}});
  my @foundations = ();
  foreach my $foundation(@dependencies) {
    next if $foundation eq 'import'; # Built-in to always have completed prior to the service being registered
    $dependency_weight++;
    my $foundation_id = $db->service_to_id($foundation);
    push @foundations, $foundation_id;
    $sth->execute($id,$foundation_id); }
  # Register Tasks on each corpus
  my $status = -5 - $dependency_weight;
  # For every import task, queue a task with the new serviceid
  my $entry_query = $db->prepare("SELECT entry from tasks where status=-1 and serviceid=1 and corpusid=?");
  my $insert_query = $db->prepare("INSERT into tasks (corpusid,serviceid,entry,status) values(?,?,?,?)");
  my $complete_foundations_query =
   $db->prepare("SELECT entry from tasks where (status=-1 or status=-2) and serviceid=? and corpusid=?");
  my $enable_tasks = $db->prepare("UPDATE tasks SET status = status + 1 WHERE entry=? and serviceid=?");
  foreach my $corpus(@{$service{corpora}}) {
    my $corpusid = $db->corpus_to_id($corpus);
    $entry_query->execute($corpusid);
    my $entry;
    $entry_query->bind_columns(\$entry);
    while ($entry_query->fetch) {
      $insert_query->execute($corpusid,$id,$entry,$status); }
    # Once the generic tasks are inserted, observe already completed successful tasks
    foreach my $foundation_id(@foundations) {
      $complete_foundations_query->execute($foundation_id,$corpusid);
      $complete_foundations_query->bind_columns(\$entry);
      while ($complete_foundations_query->fetch) { 
        $enable_tasks->execute($entry,$id);}
    }
  }
  $db->do('COMMIT');
  return $id; }

sub update_service {
  my ($db,%service) = @_;
  my $message;
  # Prepare parameters
  $service{'entry-setup'} = (($service{'entry-setup'} eq 'complex') ? 1 : 0);
  foreach my $key(qw/name version iid oldname type entry-setup/) { # Mandatory keys
    return (0,"Failed: Missing $key!") unless defined $service{$key}; }
  foreach my $key(qw/xpath url/) { # Optional keys
    $service{$key} //= '';}
  my $old_service = $db->service_description(name=>$service{oldname});
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
                          url=?, inputconverter=?, inputformat=?, outputformat=?, resource=?, entrysetup=?
                          WHERE iid=?");
  $message = $sth->execute(map {$service{$_}} 
    qw/name version iid type xpath url inputconverter inputformat outputformat resource entry-setup oldiid/);
  delete $ServiceIDs{$old_service->{name}};
  my $serviceid = $old_service->{serviceid};
  return unless $serviceid;
  $ServiceIDs{$service{name}} = $serviceid;
  $ServiceDescriptions{$service{name}} = {%service};
  # TODO: Update Dependencies
  my $clean_dependencies = $db->prepare("DELETE FROM dependencies where master=?");
  my $insert_dependencies = $db->prepare("INSERT INTO dependencies (master,foundation) values(?,?)");
  my $dependency_weight = 0;
  my @dependencies = grep {defined} ($service{inputconverter},@{$service{requires_analyses}},@{$service{requires_aggregation}});
  $clean_dependencies->execute($serviceid);
  foreach my $foundation(@dependencies) {
    next if $foundation eq 'import'; # Built-in to always have completed prior to the service being registered
    $dependency_weight++;
    my $foundation_id = $db->service_to_id($foundation);
    $insert_dependencies->execute($serviceid,$foundation_id); }
  my $status = -5 - $dependency_weight;

  # Update URL
  if ($service{url} ne $old_service->{url}) {
    # Register a new gearman URL
    my $dbhandle = db_file_connect;
    my $urls = [split("\n",$dbhandle->{gearman_urls})];
    if ($old_service->{url}) {
      @$urls = grep {$_ ne $old_service->{url}} @$urls; }
    if ($service{url}) {
      @$urls = ((grep {$_ ne $service{url}} @$urls), $service{url}); }
    $dbhandle->{gearman_urls} = join("\n",@$urls);
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
  my $delete_tasks_query = $db->prepare("DELETE from tasks where serviceid=? and corpusid=?");
  foreach my $corpusid(@$delete) {
    $delete_tasks_query->execute($serviceid,$corpusid); }
  # Takes care of rerunning all currently queued entries IFF there was a change apart from the corpus change
  if ($major_change) {
    my $update_query = $db->prepare("UPDATE tasks SET status=? where serviceid=?");
    $update_query->execute($status,$serviceid); }
  # Add new corpora
  my $entry_query = $db->prepare("SELECT entry from tasks where status=-1 and serviceid=1 and corpusid=?");
  my $insert_query = $db->prepare("INSERT into tasks (corpusid,serviceid,entry,status) values(?,?,?,?)");
  foreach my $corpusid(@$add) {
    $entry_query->execute($corpusid);
    my ($entry,@entries);
    $entry_query->bind_columns(\$entry);
    while ($entry_query->fetch) { push @entries, $entry; } 
    $db->do($db->{begin_transaction});
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
  my ($db,%options) = @_;
  my ($selector,$key);
  if ($options{name}) {
    $key = $options{name};
    $selector = "name"; }
  elsif ($options{iid}) {
    $key = $options{iid};
    $selector = "iid"; }
  my $description = $ServiceDescriptions{$key};
  if (! defined $description) {
    my $sth = $db->prepare("select * from services where $selector=?");
    $sth->execute($key);
    $description = $sth->fetchrow_hashref;
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
    $ServiceDescriptions{$key} = {%$description}; }
  return $description; }

sub mark_entry_queued {
  my ($db,$data) = @_;
  $data->{serviceid} //= $db->service_to_id($data->{service});
  $data->{corpusid} //= $db->corpus_to_id($data->{corpus});
  return unless ($data->{corpusid} && $data->{serviceid} && $data->{entry});
  my $corpusid = $data->{corpusid};
  my $serviceid = $data->{serviceid};
  my @required_services = $db->serviceid_requires($serviceid);
  my $count_complete_foundations =
    $db->prepare("SELECT count(serviceid) from tasks where entry=? and (status=-1 or status=-2) and corpusid=? and serviceid=?");
  my $count=0;
  foreach my $foundation(@required_services) {
    $count_complete_foundations->execute($foundation,$corpusid,$data->{entry});
    $count += $count_complete_foundations->fetchrow_array();
  }
  my $status = -5 - scalar(@required_services) + $count;
  # print STDERR "Required: ",scalar(@required_services),"\n";
  # print STDERR "Ready foundations: $count\n";
  # print STDERR "Set new status: $status\n";
  # print STDERR "Queuing with data: \n",Dumper($data);
  my $queue_entry_query = $db->prepare("UPDATE tasks SET status=?
      WHERE entry=? AND serviceid=? AND corpusid=?");

  my $delete_messages_query = $db->prepare(
  "DELETE L, LD from 
    (SELECT taskid from tasks WHERE status < -4) as T_todo
    INNER JOIN logs L ON (T_todo.taskid = L.taskid)
    INNER JOIN logdetails LD ON (L.messageid = LD.messageid) 
    )"); # Delete logs of all tasks yet to be completed
  $queue_entry_query->execute($status,$data->{entry},$serviceid,$corpusid);
  # Vote up for completed foundations

  $delete_messages_query->execute();
  my @enabled_services = $db->serviceid_enables($serviceid);
  foreach my $enabled_service (@enabled_services) {
    $db->mark_entry_queued({corpus=>$data->{corpus}, serviceid=>$enabled_service, entry=>$data->{entry} });
  }

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
  my @required_services = $db->serviceid_requires($serviceid);
  my $status = -5 - scalar(@required_services);

  # Start a transaction
  $db->do($db->{begin_transaction});
  if ($what) { # We have severity, category and what
    # Mark for rerun = SET the status to all affected tasks to -5-foundations
    $rerun_query = $db->prepare(" UPDATE tasks UT SET UT.status=? WHERE UT.taskid IN (
      SELECT T_filtered.taskid FROM
      (SELECT taskid FROM tasks T WHERE T.status$severity AND T.serviceid=? AND T.corpusid=?) as T_filtered 
      INNER JOIN logs L ON (T_filtered.taskid = L.taskid) 
      WHERE L.category=? and L.what=? ) ");
    $rerun_query->execute($status,$serviceid,$corpusid,$category,$what); }
  # ELSE, We have severity and category
  elsif ($category) {
    # Mark for rerun = SET the status to all affected tasks to -5-foundations
    $rerun_query = $db->prepare(
    "UPDATE tasks UT SET UT.status=? where UT.taskid IN ( 
      SELECT T_filtered.taskid FROM 
      (SELECT taskid FROM tasks T WHERE T.status$severity AND T.serviceid=? AND T.corpusid=?) as T_filtered 
      INNER JOIN logs L ON (T_filtered.taskid = L.taskid)
      WHERE L.category=?)");
    $rerun_query->execute($status,$serviceid,$corpusid,$category); }
  elsif ($severity) { # We have only severity
    # Mark for rerun = SET the status to all affected tasks to -5-foundations
    $rerun_query = $db->prepare("UPDATE tasks SET status=?
      WHERE status$severity AND serviceid=? AND corpusid=?");
    $rerun_query->execute($status,$serviceid,$corpusid); }
  else { #Simplest, but most expensive, case, rerun an entire (corpus,service) pair.
    #Mark for rerun = SET the status to all affected tasks to -5-foundations
    $rerun_query = $db->prepare("UPDATE tasks SET status=?
      WHERE serviceid=? AND corpusid=?");
    $rerun_query->execute($status,$serviceid,$corpusid); }

  #Delete all existing messages for tasks that are marked for rerun (status=-5 or smaller)
  my $delete_messages_query = $db->prepare(
    "DELETE L, LD FROM (SELECT T.taskid FROM tasks T WHERE T.status<-4) as completed_tasks 
     INNER JOIN logs L ON (completed_tasks.taskid = L.taskid)
     INNER JOIN logdetails LD ON (L.messageid = LD.messageid )");
  $delete_messages_query->execute();

  # +1 for each foundation that has already completed
  my $enable_tasks = $db->prepare("UPDATE tasks SET status = status + 1 WHERE entry=? AND serviceid=?");
  my $complete_foundation_entries =
    $db->prepare("SELECT entry FROM tasks WHERE (status=-1 or status=-2) AND serviceid=? AND corpusid=?");
  my $count=0;
  foreach my $foundation(@required_services) {
    $complete_foundation_entries->execute($foundation, $corpusid);
    my $entry;
    $complete_foundation_entries->bind_columns(\$entry);
    while ($complete_foundation_entries->fetch) {
      $enable_tasks->execute($entry,$serviceid);
    }
  }
  # TODO: Recursively rerun all enabled services where the prereq is blocked
  $db->mark_rerun_blocked($serviceid,$corpusid);
  $db->do("COMMIT");
}

# Mark blocked an entire dependency subtree
sub mark_rerun_blocked {
  my ($db,$serviceid,$corpusid) = @_;
  my @enabled_services = $db->serviceid_enables($serviceid);
  my ($mark_blocked_query, $enable_tasks);
  if ($db->{sqldbms} eq 'SQLite') {
    $mark_blocked_query = $db->prepare("UPDATE tasks SET status=? WHERE corpusid=? and serviceid=? and entry IN 
      (SELECT entry FROM tasks WHERE corpusid=? and serviceid=? and (status<-4 or status>0))");
    $enable_tasks = $db->prepare("UPDATE tasks SET status = status + 1 WHERE serviceid=? and (status<-4 or status>0) and entry IN
      (SELECT entry from tasks where corpusid=? and serviceid=? and (status=-1 or status=-2))"); }
  elsif (lc($db->{sqldbms}) eq 'mysql') {
    $mark_blocked_query = $db->prepare("UPDATE tasks SET status=? WHERE corpusid=? and serviceid=? and entry = ANY (
      SELECT * FROM (SELECT entry FROM tasks WHERE corpusid=? and serviceid=? and (status<-4 or status>0)) as _blocking_entries)");
    $enable_tasks = $db->prepare("UPDATE tasks SET status = status + 1 WHERE serviceid=? and (status<-4 or status>0) and entry = ANY (
      SELECT * FROM (SELECT entry FROM tasks WHERE corpusid=? and serviceid=? and (status=-1 or status=-2)) as _enabling_entries)"); }
  foreach my $enabled_service (@enabled_services) {
    my @required_services = $db->serviceid_requires($enabled_service);
    my $status = -5 - scalar(@required_services);
    $db->do($db->{begin_transaction});
    # First, block fully 
    $mark_blocked_query->execute($status,$corpusid,$enabled_service,$corpusid,$serviceid);
    # Then, for each successful foundation, +1 on the block 
    foreach my $required_service(@required_services) {
      $enable_tasks->execute($enabled_service,$corpusid,$required_service); }
    # Having figured out the right level of blocking, recurse into blocking the further masters
    $db->mark_rerun_blocked($enabled_service,$corpusid);
    $db->do('COMMIT');
  }
  return;
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
    if (scalar(@fields) != 5) { # Exactly 5 data points to queue
      print STDERR "Needed 5 fields, but got instead:",Dumper(\%options),"\n";
      return; }
    my $sth = $db->prepare("INSERT INTO tasks (corpusid,entry,serviceid,status) VALUES (?,?,?,?) 
      ON DUPLICATE KEY UPDATE status=?;");
    $sth->execute(@fields);
  } else {
    my @fields = grep {defined && (length($_)>0)} map {$options{$_}}
       qw/corpusid entry serviceid status/;
    if (scalar(@fields) != 4) { # Exactly 4 data points to queue
      print STDERR "Needed 4 fields, but got instead:",Dumper(\%options),"\n";
      return; }
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

sub task_report {
  my ($db,%options) = @_;
  my ($service_name,$corpus_name,$entry) = map {$options{$_}} qw(service_name corpus_name entry);
  my $serviceid = $db->service_to_id($service_name);
  my $corpusid = $db->corpus_to_id($corpus_name);
  my $task_report=[];
  my $logs_query = $db->prepare(
    "SELECT T_filtered.status, L.category, L.what, LD.details from 
     (SELECT * FROM tasks where entry=? and serviceid=? and corpusid=?) as T_filtered 
     INNER JOIN logs L ON (T_filtered.taskid = L.taskid) 
     INNER JOIN logdetails LD on (L.messageid = LD.messageid) ");
  $logs_query->execute($entry,$serviceid,$corpusid);
  my ($severity,$category,$what,$details);
  $logs_query->bind_columns(\($severity,$category,$entry,$details));
  while ($logs_query->fetch) {
    my $decoded = status_decode($severity);
    push @$task_report, "$decoded:$category:$entry $details";
  }
  return $task_report;}

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
      $report{status_decode($status)} += $count; }
    return \%report; }
  elsif ($select eq 'all') {
    $serviceid //= 1;
    my $sth = $db->prepare("SELECT count(entry) FROM tasks where serviceid=? AND corpusid=?");
    $sth->execute($serviceid,$corpusid);
    my $total;
    $sth->bind_columns(\$total);
    $sth->fetch;
    return $total; }
  else {
    $select = status_decode($select);
    return unless $select =~ /^(\d\-\<\>\=)+$/; # make sure the selector is safe
    my $sth = $db->prepare("SELECT count(entry) FROM tasks where status$select AND serviceid=? AND corpusid=? ");
    $sth->execute($serviceid,$corpusid);
    my $value;
    $sth->bind_columns(\$value);
    $sth->fetch;
    return $value; } }

sub count_messages {
  my ($db,%options)=@_;
  $options{corpusid} //= $db->corpus_to_id($options{corpus});
  $options{serviceid} //= $db->service_to_id($options{service});
  my $corpusid = $options{corpusid};
  my $serviceid = $options{serviceid};
  my $select = $options{select};
  return unless $corpusid || $serviceid;
  if (!$select && ($corpusid && $serviceid)) {
    my $sth = $db->prepare(
      "SELECT T_filtered.status, count(*) FROM
       (SELECT taskid,status FROM tasks T WHERE (T.status IN (-4,-3,-2,-1)) and serviceid=? and corpusid=?) as T_filtered
       INNER JOIN logs L ON (T_filtered.taskid = L.taskid) 
       GROUP BY T_filtered.status");
    $sth->execute($serviceid,$corpusid);
    my ($count,$status,%report);
    $sth->bind_columns(\($status,$count));
    while ($sth->fetch) {
      $report{status_decode($status)} += $count; }
    return \%report; }
  else {
    $select = status_decode($select);
    return unless $select =~ /^(\d\-\<\>\=)+$/; # make sure the selector is safe
    my $sth = $db->prepare(
      "SELECT count(*) FROM
       (SELECT taskid FROM tasks WHERE status$select and serviceid=? and corpusid=?) as T_filtered 
       INNER JOIN logs ON (T_filtered.taskid = logs.taskid)");
    $sth->execute($serviceid,$corpusid);
    my $value;
    $sth->bind_columns(\$value);
    $sth->fetch;
    return $value; } }

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
    my $sth = $db->prepare("SELECT entry, details from 
       (SELECT * FROM tasks WHERE tasks.status=$severity and tasks.serviceid=? and tasks.corpusid=?) as T_filtered 
       INNER JOIN logs ON (T_filtered.taskid = logs.taskid) 
       INNER JOIN logdetails ON (logs.messageid = logdetails.messageid) 
       WHERE logs.category=? and logs.what=? 
       ORDER BY entry \n"
      . ($options->{limit} ? "LIMIT ".$options->{limit}." \n" : '')
      . ($options->{from} ? "OFFSET ".$options->{from}." \n" : ''));
    $sth->execute($serviceid,$corpusid,$options->{category},$options->{what});
    my ($entry, $details);
    $sth->bind_columns(\($entry,$details));
    while ($sth->fetch) {
      push @entries, [$entry,$details,undef];
      # @entries = map {[$name, $content, $url] }
    }}
  else {
    # Only return results if OK (TODO: URL?)
    my $status = status_encode($options->{select});
    my $sth = $db->prepare("SELECT entry from tasks where status$status and serviceid=? and corpusid=? "
      . " ORDER BY entry \n"
      . ($options->{limit} ? "LIMIT ".$options->{limit}." \n" : '')
      . ($options->{from} ? "OFFSET ".$options->{from}." \n" : ''));
    $sth->execute($serviceid,$corpusid);
    #@entries = [$name, undef, $url ]
    my $name;
    $sth->bind_columns(\$name);
    while ($sth->fetch) {
      push @entries, [$name,"OK",undef]; } }
  \@entries; }

sub get_result_summary {
 my ($db,%options) = @_; 
 my $result_summary = {};
 return unless $options{corpus} && $options{service};
 my $corpusid = $db->corpus_to_id($options{corpus});
 my $serviceid = $db->service_to_id($options{service});
 my $count_clause = ($options{countby} eq 'message') ? '*' : 'distinct(T_filtered.taskid)';
  if (! $options{severity}) {
    # Top-level summary, get all severities and their counts:
    if ($options{countby} eq 'message') {
      $result_summary = $db->count_messages(%options); }
    else {
      $result_summary = $db->count_entries(%options); } }
  elsif (! $options{category}) {
    $options{severity} = status_code($options{severity});
    my $types_query = $db->prepare(
      "SELECT category, count($count_clause) as counted FROM
        ( SELECT * FROM tasks WHERE status=? AND serviceid=? AND corpusid=?) as T_filtered 
        INNER JOIN logs ON (T_filtered.taskid = logs.taskid)
       group by category
       ORDER BY counted DESC
       LIMIT 100;");
    $types_query->execute($options{severity},$serviceid,$corpusid);
    my ($category,$count);
    $types_query->bind_columns( \($category,$count));
    while ($types_query->fetch) {
      $result_summary->{$category} = $count if $count>0; } }
  else {
    # We have both severity and category, query for "what" component
    $options{severity} = status_code($options{severity});
    my $types_query = $db->prepare(
      "SELECT what, count($count_clause) as counted FROM 
       (SELECT * FROM tasks WHERE status=? AND serviceid=? AND corpusid=? ) as T_filtered
       INNER JOIN logs ON (T_filtered.taskid = logs.taskid)
      WHERE logs.category=? group by what
      ORDER BY counted DESC
      LIMIT 100");
    $types_query->execute($options{severity},$serviceid,$corpusid,$options{category});
    my ($what,$count);
    $types_query->bind_columns( \($what,$count));
    while ($types_query->fetch) {
      $result_summary->{$what} = $count if $count>0; } }
  return $result_summary; }

sub status_decode {
  my ($status_code) = @_;
  my $decoded_value;
  if ($status_code == -1)    {$decoded_value = 'ok'}
  elsif ($status_code == -2) {$decoded_value = 'warning'}
  elsif ($status_code == -3) {$decoded_value = 'error'}
  elsif ($status_code == -4) {$decoded_value = 'fatal'}
  elsif ($status_code == -5) {$decoded_value = 'queued'}
  elsif ($status_code > 0)   {$decoded_value = 'processing' }
  else                       {$decoded_value = 'blocked' }
  return $decoded_value; }

our %status_encoding_table = (
  ok => '=-1',
  warning => '=-2',
  error => '=-3',
  fatal => '=-4',
  queued => '=-5',
  processing => '>0',
  blocked => '<-5' );
sub status_encode {
  my ($status) = @_;
  return $status_encoding_table{$status}; }

our %status_codes_table = (
  ok => -1,
  warning => -2,
  error => -3,
  fatal => -4,
  queued => -5,
  processing => 1,
  blocked => -6 );
sub status_code {
  my ($status) = @_;
  return $status_codes_table{$status}; }

sub repository_size {
 return 1; }# TODO

sub mark_limbo_entries_queued {
  my ($db) = @_;
  # Entries in limbo have already had their follow-up services blocked 
  # AMD their messages erased, so all we need to do is make them available for processing again
  my $sth = $db->prepare("UPDATE tasks SET status=-5 WHERE status>0");
  $sth->execute(); }

sub fetch_tasks {
  my ($db,%options) = @_;
  my $available_workers = available_workers($options{hosts},$options{port}); # Only fetch tasks for services that we have available
  $$available_workers{init_v0_1} = 1;
  my @available_serviceids = sort grep {defined} map {$db->serviceiid_to_id($_)} keys %$available_workers if defined $available_workers;

  my $size = $options{size};
  my $mark = int(1+rand(10000));
  my (%row,@tasks);

  my $sth;
  $sth = $db->prepare("UPDATE tasks SET status=? WHERE status=-5 AND serviceid IN (".join(',',@available_serviceids).") LIMIT ?");
  $db->safe_execute($sth,$mark,$size);
  $sth = $db->prepare("SELECT taskid,serviceid,entry from tasks where status=?");
  $sth->execute($mark);
  
  $sth->bind_columns( \( @row{ @{$sth->{NAME_lc} } } ));
  while ($sth->fetch) {
    # Name of the function:
    next unless $row{serviceid};
    $row{iid}=$db->serviceid_to_iid($row{serviceid});
    push @tasks, {%row}; }
  undef %row;
  
  return($mark,\@tasks); }

sub complete_tasks {
  my ($db,$results) = @_;
  return unless @$results;
  # Insert in TaskDB
  $db->do($db->{begin_transaction});
  my $mark_complete = $db->prepare("UPDATE tasks SET status=? WHERE taskid=?");
  my $add_message = $db->prepare("INSERT INTO logs (taskid, category, what) values(?,?,?)");
  my $add_details = $db->prepare("INSERT INTO logdetails (messageid, details) values(?,?)");
  # Decrease the requirements on any blocked jobs by this service, for this entry.
  my $enable_tasks = $db->prepare("UPDATE tasks SET status = status + 1 WHERE entry=? and serviceid=?");
  foreach my $result(@$results) {
    my $entry = $result->{entry};
    my $taskid = $result->{taskid};
    my $iid = $result->{service};
    my $status = $result->{status};
    my $serviceid = $db->serviceiid_to_id($iid);
    # Mark task as completed
    $db->safe_execute($mark_complete,$result->{status},$taskid);
    # Insert new messages
    foreach my $message (@{$result->{messages}||[]}) {
      my $severity = status_code($message->{severity});
      next unless ($severity # Discard non-core severity messages, such as LaTeXML's "info"
      && ($severity == $status)); # [Optimization] Only record messages of the same severity as the job, to save space
      $db->safe_execute($add_message,$taskid, $message->{category}, $message->{what});
      my $messageid = $db->last_inserted_id();
      $db->safe_execute($add_details,$messageid,$message->{details});
    }
    # Propagate in dependencies
    if (($status == -1) || ($status == -2)) { # If warning or OK job
      my @enables = $db->serviceid_enables($serviceid);
      foreach my $enabled_service(@enables) { # Enable follow-up services
        $db->safe_execute($enable_tasks,$entry,$enabled_service); } } }
  $db->do('COMMIT'); }

1;
__END__