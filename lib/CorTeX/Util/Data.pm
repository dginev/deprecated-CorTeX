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

# Parses a log string which follows the LaTeXML convention
# (described at http://dlmf.nist.gov/LaTeXML/manual/errorcodes/index.html)
sub parse_log {
  my ($log_content) = @_;
  # Quit unless we have some data
  return unless length($log_content);
  # Obtain the individual lines
  my @lines = split("\n",$log_content);
  my @messages;
  my $maybe_details = 0;

  while (@lines) {
    my $line = shift @lines;
    # Skip empty lines
    next unless $line;
    # If we have found a message header and we're collecting details:
    if ($maybe_details) {
      # If the line starts with tab, we are indeed reading in details
      if ($line =~ /^\t/) {
        # Append details line to the last message"
        $messages[-1]->{details}.="\n$line";
        next; # This line has been consumed, next
      } else {
        # Otherwise, no tab at the line beginning means last message has ended
        $maybe_details=0;
      }}
    # Since this isn't a details line, check if it's a message line:
    if ($line =~ /^([^ :]+)\:([^ :]+)\:([^ ]+)(\s(.*))?$/) {
      # Indeed a message, so record it:
      my $message = {severity=>lc($1),category=>lc($2),what=>lc($3),details=>$5};
      # Prepare to record follow-up lines with the message details:
      $maybe_details=1;
      # Add to the array of parsed messages
      push @messages, $message;}
    else {
      # Otherwise line is just noise, continue...
      $maybe_details=0;
    }}
  # Return the parsed messages  
  return \@messages; }

1;

__END__