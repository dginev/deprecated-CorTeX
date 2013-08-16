# /=====================================================================\ #
# |  CorTeX Framework Utilities                                         | #
# | TeX -> XHTML conversion module                                      | #
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
package CorTeX::Util::Convert;
use warnings;
use strict;
use Mojo::UserAgent;
use Mojo::ByteStream qw(b);
use Mojo::JSON;
use Data::Dumper;
use CorTeX::Util::RDFWrappers qw(xsd);
use CorTeX::Util::Data qw(log_to_triples);

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(convert_zip convert_snippet);

sub convert_zip {
  my %opts = @_;
  my ($url, $zip_data, $name,$proxy_url) = map {$opts{$_}} qw(converter payload name proxy_url);
  my $userAgent = Mojo::UserAgent->new;
  $userAgent = $userAgent->http_proxy($proxy_url) if $proxy_url;
  my $tx = $userAgent->post($url => {'Content-Type'=>'multipart/form-data', 'X-File-Type'=>'application/zip', 'X-File-Name'=>$name} => b($zip_data)->b64_decode);
  my $zip_response = b($tx->res->body)->b64_encode;
  return $zip_response;
}

sub convert_snippet {
  my %opts = @_;
  my ($url, $payload, $proxy_url) = map {$opts{$_}} qw(converter payload proxy_url);
  my $userAgent = Mojo::UserAgent->new;
  $userAgent = $userAgent->http_proxy($proxy_url) if $proxy_url;
  my $tx = $userAgent->post_form($url, 'UTF-8', {tex=>$payload});
  my $response = $tx->res->body;
  $response = Mojo::JSON->decode($response) if $response;
  return $response;
}

# TODO: Move this to an RDF API module !!!
our @chars=('a'..'z','A'..'Z','0'..'9');
sub new_blank {
  my $id=q{};
  foreach (1..15)
    {
      # rand @chars will generate a random 
      # number between 0 and scalar @chars
      $id.=$chars[rand @chars];
    }
  "_:bnode$id";
}

1;
