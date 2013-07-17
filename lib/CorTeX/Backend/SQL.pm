# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | SQL Databases Backend Connector                                     | #
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
package CorTeX::Backend::SQL;

use warnings;
use strict;

use DBI;
use Mojo::ByteStream qw(b);

# Design: One database handle per CorTeX::Backend::SQL object
#  ideally lightweight, only store DB-specific data in the object

sub new {
  my ($class,%input)=@_;
  # White-list the options we care about:
  my %options;
  $options{sqluser} = $input{sqluser};
  $options{sqlpass} = $input{sqlpass};
  $options{sqldbname} = $input{sqldbname};
  $options{sqlhost} = $input{sqlhost};
  $options{sqldbms} = lc($input{sqldbms});
  $options{query_cache} = $input{query_cache} || {};
  $options{handle} = $input{handle};
  my $self = bless \%options, $class;
  if (($options{sqldbms} eq 'SQLite') && ((! -f $options{sqldbname})||(-z $options{sqldbname}))) {
    # Auto-vivify a new SQLite database, if not already created
    if (! -f $options{sqldbname}) {
      # Touch a file if it doesn't exist
      my $now = time;
      utime $now, $now, $options{sqldbname}; 
    }
    $self->reset_db;
  }
  return $self;
}

# Methods:

# safe - adverb for connection to the database and returning a handle for further "deeds"
sub safe {
  my ($self)=@_;
  if (defined $self->{handle} && $self->{handle}->ping) {
    return $self->{handle};
  } else {
    my $dbh = DBI->connect("DBI:". $self->{sqldbms} .
         ":" . $self->{sqldbname},
         $self->{sqluser},
         $self->{sqlpass},
         {
          host => $self->{sqlhost},
          RaiseError => 1,
          AutoCommit => 1
         }) || die "Could not connect to database: $DBI::errstr";
    $dbh->do('PRAGMA cache_size=50000;') if $self->{sqldbms} eq 'SQLite';
    $self->{handle}=$dbh;
    $self->_recover_cache;
    return $dbh;
  }
}

# done - adverb for cleaning up. Disconnects and deletes the statement cache

sub done {
  my ($self,$dbh)=@_;
  $dbh = $self->{handle} unless defined $dbh;
  $dbh->disconnect();
  $self->{handle}=undef;
}

###  Safe interfaces for the DBI methods

sub disconnect { done(@_); } # Synonym for done
sub do {
  my ($self,@args) = @_;
  $self->safe->do(@args);
}
sub execute {
  my ($self,@args) = @_;
  $self->safe->execute(@args);
}
sub ping {
  my ($self,@args) = @_;
  $self->safe->ping(@args);
}

sub prepare {
  # Performs an SQL statement prepare and returns, maintaining a cache of already
  # prepared statements for potential re-use..
  #
  # NOTE: it is only useful to use these for immutable statements, with bind
  # variables or no variables.
  my ($self,$statement) = @_;
  my $query_cache = $self->{query_cache};
  if (! exists $query_cache->{$statement}) {
    $query_cache->{$statement} = $self->safe->prepare($statement);
  }
  return $query_cache->{$statement};
}

### Internal helper routines:

sub _recover_cache {
  my ($self) = @_;
  my $query_cache = $self->{query_cache};
  foreach my $statement (keys %$query_cache) {
    $query_cache->{$statement} = $self->safe->prepare($statement); 
  }
}

### API for Initializing a SQLite Database:
sub reset_db {
  my ($self) = @_;
  my $type = lc($self->{sqldbms});
  $self = $self->safe; # unsafe but faster...
  if ($type eq 'sqlite') {
    # Request a 20 MB cache size, reasonable on all modern systems:
    $self->do("PRAGMA cache_size = 20000; ");
    # Tasks
    $self->do("DROP TABLE IF EXISTS tasks;");
    $self->do("CREATE TABLE tasks (
      taskid integer primary key AUTOINCREMENT,
      corpusid integer(1),
      serviceid integer(2),
      entry varchar(200),
      status integer(2)
    );");
    $self->do("CREATE INDEX statusidx ON tasks(status);");
    $self->do("create index corpusidx on tasks(corpus);");
    $self->do("create index entryidx on tasks(entry);");
    $self->do("create index serviceidx on tasks(service);");
    # Corpora
    $self->do("DROP TABLE IF EXISTS corpora;");
    $self->do("CREATE TABLE corpora (
      corpusid integer(1) primary key AUTOINCREMENT,
      name varchar(200)
    );");
    $self->do("create index corpusnameidx on corpora(name);");
    # Services 
    $self->do("DROP TABLE IF EXISTS services;");
    $self->do("CREATE TABLE services (
      serviceid integer(2) primary key AUTOINCREMENT,
      name varchar(200)
    );");
    $self->do("create index servicenameidx on services(name);"); 
  }
  elsif ($type eq 'mysql') {
    # Tasks
    $self->do("DROP TABLE IF EXISTS tasks;");
    $self->do("CREATE TABLE tasks (
      taskid INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
      serviceid mediumint,
      corpusid tinyint,
      entry varchar(200),
      status mediumint
    );");
    $self->do("CREATE INDEX statusidx ON tasks(status);"); 
    $self->do("create index corpusidx on tasks(corpus);");
    $self->do("create index entryidx on tasks(entry);");
    $self->do("create index serviceidx on tasks(service);");
    # Corpora
    $self->do("DROP TABLE IF EXISTS corpora;");
    $self->do("CREATE TABLE corpora (
      corpusid tinyint NOT NULL AUTO_INCREMENT PRIMARY KEY,
      name varchar(200)
    );");
    $self->do("create index corpusnameidx on corpora(name);");
    # Services
    $self->do("DROP TABLE IF EXISTS services;");
    $self->do("CREATE TABLE services (
      serviceid mediumint NOT NULL AUTO_INCREMENT PRIMARY KEY,
      name varchar(200)
    );");
    $self->do("create index servicenameidx on services(name);");

  }
  else {
    print STDERR "Error: SQL DBMS of type=$type isn't recognized!\n";
  }
  return;
}

# API Layer

sub delete_corpus {
  my ($self,$corpus) = @_;
  return unless ($corpus && (length($corpus)>0));
  return $self->purge(corpus=>$corpus);
}

sub queue {
  my ($self,%options) = @_;
  # Note: The two "status" lookups are not a typo, we need both to have the "on duplicate" clause set:
  my @fields = grep {defined && (length($_)>0)} map {$options{$_}} qw/corpus entry service status status/;
  return unless scalar(@fields) == 5; # Exactly 5 data points to queue
  my $sth = $self->prepare("INSERT INTO tasks (corpus,entry,service,status) VALUES (?,?,?,?) 
    ON DUPLICATE KEY UPDATE status=?;");
  $sth->execute(@fields);
  $sth->finish();
  return 1;
}

sub purge {
  my ($self,%options) = @_;
  my $entry = $options{entry} ? "entry=?" : "";
  my $corpus = $options{corpus} ? "corpus=?" : "";
  my $service = $options{service} ? "service=?" : "";
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

__END__

=pod 

=head1 NAME

C<CorTeX::Backend::SQL> - DBI interface for CorTeX::Backend

=head1 SYNOPSIS

  use CorTeX::Backend;
  $backend=CorTeX::Backend->new(sqluser=>'cortex',sqlpass=>'cortex',sqldbname=>"cortex",
    sqlhost=>"localhost", sqldbms=>"mysql", verbosity=>0|1,);

  # Directly access the CorTeX::Backend::SQL object as $db 
  $db = $backend->sql;

  # Low-level Methods
  $connection_alive = $db->ping;
  $statement_handle = $db->prepare('DBI sql statement');
  $db->execute('DBI sql statement');
  $disconnect_successful = $db->done;

  # CorTeX API

=head1 DESCRIPTION

Interface to DBI's SQL logic. Provides an Object-oriented approach, 
  where each CorTeX::Backend::SQL object contains a single DBI handle, 
  together with a cache of prepared statements.

The documentation assumes basic familiarity with DBI.

This library is a clone of L<NNexus::DB>, written by the same author.

=head2 METHODS

=over 4

=item C<< $backend=CorTeX::Backend->new(%options); >>

Creates a new C<CorTeX::Backend::SQL> object.
  Required options are sqluser, sqlpass, sqldbname, sqlhost and sqldbms, so that
  the database connection can be successfully created.

=item C<< $db = $backend->sql; >>

Access the CorTeX::Backend::SQL object directly, as $db.

=item C<< $response = $db->DBI_handle_command; >>

The C<CorTeX::Backend::SQL> methods are interfaces to their counterparts in L<DBI>, with the addition of a query cache and
  a safety mechanism that auto-vivifies the connection when needed.

=item C<< $sth = $db->safe; >>

The F<safe> adverb returns a L<DBI> handle, taking extra care that the handle is properly connected to
  the respective DB backend.
  While you could take the L<DBI> handle and use it directly (it is the return value of the F<safe> method),
  avoid that approach.

Instead, always invoke L<DBI> commands through the C<CorTeX::Backend::SQL> object or explicitly use the F<safe> adverb to get a handle,
  e.g. C<$db-<gt>execute>, C<$db-<gt>prepare> or C<$sth = $db-<gt>safe>
  The cache of prepared statements is also rejuvenated whenever a new L<DBI> handle is auto-created.

=item C<< $disconnect_successful = $db->done; >>

Disconnects from the backend and destroys the L<DBI> handle.
  Note that the cache of prepared statements will be rejuvenated
  when a new L<DBI> handle is initialized.

=item C<< $statement_handle = $db->prepare; >>

Cached preparation of SQL statements. Internally uses the F<safe> adverb, to ensure robustness.
  Each SQL query and its L<DBI> statement handle is cached, to avoid multiple prepare calls on the same query string.

=back

=head2 CorTeX API

=over 4

=item C<< my $success = $db->queue(corpus=>$corpus,entry=>$entry,service=>$service,status=>$status); >>

All four input parameters are mandatory.

Updates the status of the given corpus:entry and service.
Legend:

=over 8

=item 0: Ready for processing

=item -1: Completed

=item -2: Unmet prerequisites

=item >0: Dispatched for processing, the number is typically the Gearman Job ID

=back

=item C<< my $success = $db->purge(corpus=>$corpus,entry=>$entry,service=>$service,status=>$status); >>

Provide at least one of the four input parameters to purge the respective subset of the tasks table.

=back

=head1 SEE ALSO

L<DBI>, L<NNexus::DB>

=head1 AUTHOR

Deyan Ginev <d.ginev@jacobs-university.de>

=head1 COPYRIGHT

 Research software, produced as part of work done by 
 the KWARC group at Jacobs University Bremen.
 Released under the GNU Public License

=cut
