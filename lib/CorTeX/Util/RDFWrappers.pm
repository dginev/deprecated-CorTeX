# /=====================================================================\ #
# |  CorTeX Framework Utilities                                         | #
# | RDF Wrapper utilities for the Sesame SPARQL endpoint                | #
# |=====================================================================| #
# | Part of the MathSearch project: http://trac.kwarc.info/lamapun      | #
# |  Research software, produced as part of work done by:               | #
# |  the KWARC group at Jacobs University,                              | #
# | Copyright (c) 2012                                                  | #
# | Released under the GNU Public License                               | #
# |---------------------------------------------------------------------| #
# | Deyan Ginev <d.ginev@jacobs-university.de>                  #_#     | #
# | http://kwarc.info/people/dginev                            (o o)    | #
# \=========================================================ooo==U==ooo=/ #
package CorTeX::Util::RDFWrappers;

use URI::Escape;
use HTML::Entities qw(decode_entities encode_entities_numeric);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(wrap_Turtle_triple wrap_Turtle_triple_noprefix wrap_SPARQL_Update wrap_SPARQL_Updates wrap_SPARQL_Query xsd unique_varname sesame_unescape); # symbols to export on request
our %EXPORT_TAGS = (all=>[qw(wrap_Turtle_triple wrap_Turtle_triple_noprefix wrap_SPARQL_Update wrap_SPARQL_Updates wrap_SPARQL_Query xsd unique_varname sesame_unescape)]);

our $PREFIX_LIST = {
  rdfs=>'http://www.w3.org/2000/01/rdf-schema#',
  xsd=>'http://www.w3.org/2001/XMLSchema#',
	build=>'http://lamapun.mathweb.org/ns/buildsystem#'
};
our $TURTLE_PREFIX = join("\n", map {'@prefix '.$_.': <'.$PREFIX_LIST->{$_}.'>. '}
	keys %$PREFIX_LIST);
our $SPARQL_PREFIX = join("\n", map {'PREFIX '.$_.': <'.$PREFIX_LIST->{$_}.'> '}
	keys %$PREFIX_LIST);

#TODO: Clearly a very hardcoded case of URL URL String, needs to be generalized
# A CPAN module must exist for this... also consider switching to the Java API!
sub wrap_Turtle_triple {
  my ($s,$p,$o,$exist_base) = @_;
  my $triple = wrap_Turtle_triple_noprefix($s,$p,$o);
  my $exist_prefix = '@prefix exist: <'.$exist_base.'/rest#>. ';
  $TURTLE_PREFIX.$exist_prefix.$triple;
}
sub wrap_Turtle_triple_noprefix {
  my ($s,$p,$o) = @_;
  # Take care of explicit resources, otherwise blank nodes:
  $s = "<$s>" unless $s=~/^\_\:/;
  my $triple = "$s $p $o . ";
}

sub wrap_SPARQL_Update {
  my ($old,$new,$where,$graph,$exist_base) = @_;
  wrap_SPARQL_Updates([{old=>$old,new=>$new,where=>$where}],$graph,$exist_base);
}

sub wrap_SPARQL_Updates {
  my ($updates,$graph,$exist_base) = @_;
  # Take care of explicit resources, otherwise blank nodes:
  my $exist_prefix = 'PREFIX exist: <'.$exist_base.'/rest#>';
  my $update_batch = q{};
  my ($all_old,$all_new,$all_where) = ([],[],[]);
  my $unique_vars = {};
  foreach my $update(@$updates) {
    my ($old,$new,$where) = map {$update->{$_}} qw(old new where);
    $where = $old unless defined $where;
    push $all_old, @$old;
    push $all_new, @$new;
    push $all_where, @$where;
  }
  $update_batch .= wrap_SPARQL_Update_noprefix($all_old,$all_new,$all_where,$graph)."\n\n";
  my $wrapped = "update=".$SPARQL_PREFIX."\n".$exist_prefix."\n".$update_batch;
  #print STDERR "\n\n",$wrapped,"\n\n";
  $wrapped;
}


sub wrap_SPARQL_Update_noprefix {
  my ($old,$new,$where,$graph) = @_;
  # Take care of explicit resources, otherwise blank nodes:
  if ($old) {
    foreach (@$old) {
      $_->{subject} = "<".$_->{subject}.">" unless ($_ && ($_->{subject} =~ /^(\_\:)|\<|\?/));
    }
  }
  if ($new) {
    foreach (@$new) {
      $_->{subject} = "<".$_->{subject}.">" unless ($_ && ($_->{subject} =~ /^(\_\:)|\<|\?/));
    }
  }
  foreach (@$where) {
    $_->{subject} = "<".$_->{subject}.">" unless ($_ && ($_->{subject} =~ /^(\_\:)|\<|\?/));
  }
  my @where_optional = (grep {$_->{optional}} @$where) || ();
  @$where = grep {! $_->{optional}} @$where;
  my $update_query = "WITH <$graph> \n"
  . ($old ? "DELETE { ".join(" ",map { $_->{subject}." ".$_->{predicate}." ".$_->{object}."."} @$old)." } \n" : '')
  . ($new ? "INSERT { ".join(" ",map { $_->{subject}." ".$_->{predicate}." ".$_->{object}."."} @$new)." } \n" : '')
  ."WHERE { ".join(" ",map { $_->{subject}." ".$_->{predicate}." ".$_->{object}."."} @$where)."  "
            .join(" ",map {" OPTIONAL { ".$_->{subject}." ".$_->{predicate}." ".$_->{object}." } ."} @$where_optional)." } ";
  $update_query;
}


sub wrap_SPARQL_Query {
  my ($query,$exist_base) = @_;
  my $exist_prefix = 'PREFIX exist: <'.$exist_base.'/rest#>';
  my $wrapped = "query=".$SPARQL_PREFIX."\n".$exist_prefix."\n".$query;
  #print STDERR "Querying for : \n", $wrapped,"\n\n";
  $wrapped;
}

sub xsd {
  my ($data,%opts) = @_;
  return unless defined $data; # Empty values shouldn't be wrapped
  my $type = 'string';
  $type = 'integer' if $data=~/^[-]?\d+$/;
  if ($type eq 'string') {
    $data = encode_entities_numeric($data);
    $data =~ s/\\/&#92;/g;
    $data = uri_escape($data);
    #$data =~  s/"/\\"/g;
    $data = uri_escape($data) if $opts{get};
  }
  '"'.$data.'"^^xsd:'.$type;
}

sub unique_varname {
  my @chars=('a'..'z');
  my $random_string;
  $random_string.=$chars[rand @chars] foreach (1..10);
  return '?'.$random_string;
}

sub sesame_unescape {
  my ($data) = @_;
  decode_entities(uri_unescape($data));
}

1;

__END__

=pod 

=head1 NAME

C<CorTeX::Util::RDFWrappers> - Convenience Wrappers/Constructors for RDF Turtle and Sparql objects

=head1 SYNOPSIS

    use CorTeX::Util::RDFWrappers;
    my $sparql_query = wrap_SPARQL_Query($unwrapped_query);
    ...

=head1 DESCRIPTION

TODO

=head2 METHODS

=over 4

=item C<< my $sparql_query = wrap_SPARQL_Query($unwrapped_query); >>

TODO

=back

=head1 AUTHOR

Deyan Ginev <d.ginev@jacobs-university.de>

=head1 COPYRIGHT

 Research software, produced as part of work done by 
 the KWARC group at Jacobs University Bremen.
 Released under the GNU Public License

=cut
