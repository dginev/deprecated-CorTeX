# /=====================================================================\ #
# |  CorTeX Framework Utilities                                         | #
# | Data processing                                                     | #
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

package CorTeX::Util::Data;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(log_to_triples parse_log);

sub log_to_triples {
  my ($entry,$log_content) = @_;
  #print STDERR "\n\n$log_content\n\n";
  my $messages = parse_log($log_content);

  my @triples =  map {my $blank = new_blank();
                     # Remove local info from details:
                     if ($_->{details} && $_->{details}=~/^(.+)\sfrom\s/) {
                       $_->{details}=$1;
                     }
                     [$entry,"build:".$_->{severity},$blank] ,
                       ((defined $_->{category}) && length($_->{category})>0) ? ([$blank,"build:category",xsd($_->{category})]) : (),
                       ((defined $_->{what}) && length($_->{what})>0) ? ([$blank,"build:what",xsd($_->{what})]) : (),
                       ((defined $_->{details}) && length($_->{details})>0) ? ([$blank,"build:details",xsd($_->{details})]) : ();
                    } @$messages;
  #print STDERR "\n\n",Dumper(@triples),"\n\n";
  @triples = () unless @triples;
  \@triples;
}

sub parse_log {
  my ($log_content) = @_;
  return unless length($log_content);
  my @lines = split("\n",$log_content);
  my @messages;
  my $maybe_details = 0;

  while (@lines) {
    my $line = shift @lines;
    next unless $line;
    # If we're still expecting details:
    if ($maybe_details) {
      if ($line =~ /^\t/) {
        $messages[-1]->{details}.="\n$line";
        next; # This line has been consumed, next
      } else {
        $maybe_details=0; # The last message has ended
      }}
    # Since this isn't a details line, check if it's a message line:
    if ($line =~ /^([^ :]+)\:([^ :]+)\:([^ ]+)(\s(.*))?$/) {
      my $message = {severity=>lc($1),category=>lc($2),what=>lc($3),details=>$5};
      $maybe_details=1;
      push @messages, $message;}
    else {
      $maybe_details=0;
    }}  
  return \@messages; }

1;

__END__