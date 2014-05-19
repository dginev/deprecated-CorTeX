# /=====================================================================\ #
# |  CorTeX Framework Utilities                                         | #
# | Gearman communication helpers                                       | #
# |=====================================================================| #
# |  Research software, produced as part of work done by:               | #
# |  the KWARC group at Jacobs University,                              | #
# | Copyright (c) 2012-2014                                             | #
# | Released under the GNU Public License                               | #
# |---------------------------------------------------------------------| #
# | Deyan Ginev <d.ginev@jacobs-university.de>                  #_#     | #
# | http://kwarc.info/people/dginev                            (o o)    | #
# \=========================================================ooo==U==ooo=/ #
package CorTeX::Util::Gearman;
use strict;
use warnings;
use Net::Telnet;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(available_workers);

sub available_workers {
  my ($hosts, $port) = @_;
  $port = '4730' unless defined $port;
  my %services;
  foreach my $host (@$hosts) {
    my $gearman_server = Net::Telnet->new(
      Host => $host,
      Port => $port,
      Timeout => 1);    #Attempt connecting to Gearman
    $gearman_server->telnetmode(0);

    my $ok = $gearman_server->open();
    if ($ok) {
      $gearman_server->print('STATUS');
      my $report = $gearman_server->get();
      if ($report) {
        my @lines = split("\n",$report);
        pop @lines; # Drop trailing .
        foreach my $line(@lines) {
          my ($service, $count);
          if ($line =~ /^(\S+)/) {
            $service = $1; }
          if ($line =~ /(\S+)$/) {
            $count = $1;
          }
          $services{$service} += $count if ($service && ($count > 0));
        }
      }
      $gearman_server->close();
    }
  }
  return \%services;
}

1;

__END__
