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

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(queue purge delete_corpus);

our %CorpusIDs = ();
our %ServiceIDs = ();

sub delete_corpus {
  my ($self,$corpus) = @_;
  return unless ($corpus && (length($corpus)>0));
  return $self->purge(corpus=>$corpus);
}

sub queue {
  my ($self,%options) = @_;
  my $corpus = $options{corpus};
  my $service = $options{service};
  my $corpusid = $CorpusIDs{$corpus};
  if (! defined $corpusid) {
  	# TODO: Do a lookup in the TaskDB
  }
  if (! defined $serviceid) {
  	# TODO: Do a lookup in the TaskDB
  }
  my $serviceid = $ServiceIDs{$service};
  # Note: The two "status" lookups are not a typo, we need both to have the "on duplicate" clause set:
  my @fields = grep {defined && (length($_)>0)} map {$options{$_}} qw/corpus entry service status status/;
  return unless scalar(@fields) == 5; # Exactly 5 data points to queue
  my $sth = $self->prepare("INSERT INTO tasks (corpusid,entry,serviceid,status) VALUES (?,?,?,?) 
    ON DUPLICATE KEY UPDATE status=?;");
  $sth->execute(@fields);
  $sth->finish();
  return 1;
}

sub purge {
  my ($self,%options) = @_;
  my $entry = $options{entry} ? "entry=?" : "";
  my $corpus = $options{corpus} ? "corpusid=?" : "";
  my $service = $options{service} ? "serviceid=?" : "";
  my $status = $options{status} ? "status=?" : "";
  my @fields = grep {length($_)>0} ($entry,$corpus,$service,$status);
  return unless @fields;
  my $where_clause = join(" AND ",@fields);
  my $sth = $self->prepare("DELETE FROM tasks WHERE ".$where_clause.";");
  $sth->execute(grep {defined} map {$options{$_}} qw/entry corpus service status/);
  $sth->finish();
  return 1;
}

1;