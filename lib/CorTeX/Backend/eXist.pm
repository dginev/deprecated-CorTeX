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
package CorTeX::Backend::eXist;

use warnings;
use strict;

use Carp;
use RPC::XML;
use RPC::XML::Client;
use Mojo::ByteStream qw(b);

sub new {
  my ($class,%opts)=@_;
  # Output options
  my $options = RPC::XML::struct->new(
    'indent' => 'yes',
    'encoding' => 'UTF-8',
    'variables' => RPC::XML::struct->new('query' => 'corrupt*')
  );
  print STDERR "connecting to ".$opts{exist_url}."...\n" if ($opts{verbosity}>0);
  $opts{base_url}=$opts{exist_url};
  $opts{base_url} =~ s/\/+$//; # No trailing slashes
  $opts{xmlrpc_url} = $opts{base_url} . '/xmlrpc';
  $opts{rest_url} = $opts{base_url} . '/rest';
  my $client = RPC::XML::Client->new($opts{xmlrpc_url});
  my $resp = $client->send_request('system.listMethods');
  if (ref $resp) {
    return bless {%opts, client=>$client, options=>$options}, $class;
  } else {
    return;
  }
}

sub set_host {
  my ($self,$url)=@_;
  $url =~ s/\/+$//;
  print STDERR "connecting to ".$url."...\n" if ($self && $self->{verbosity}>0);
  $self->{base_url} = $url; # No trailing slashes
  $self->{xmlrpc_url} = $url.'/xmlrpc';
  $self->{rest_url} = $url.'/rest';
  $self->{client} = RPC::XML::Client->new($self->{xmlrpc_url});
}
sub URL_base { $_[0]->{base_url}; }
sub URL_xmlrpc { $_[0]->{xmlrpc_url}; }
sub URL_rest { $_[0]->{rest_url}; }

sub xmlrpc_query {
  my ($self,$query,%options)=@_;
  #print STDERR "Executing $query ...\n";
  # Execute the query. The method call returns a handle
  # to the created result set.
  my $req;
  $req = RPC::XML::request->new("executeQuery",
				  RPC::XML::base64->new($query),
				  "UTF-8", $self->{options});
  my $response = $self->_process($req);
  my $result_id = (ref $response) && ($response->value);
  # Get the number of hits in the result set
  my ($hits,$first);
  if (defined $result_id) {
    $req = RPC::XML::request->new("getHits", $result_id);
    $response = $self->_process($req);
    $hits = (ref $response) && ($response->value);
    if ($hits>0) {
      $req = RPC::XML::request->new("retrieve", $result_id, 0, {});
      $response = $self->_process($req);
      $first = (ref $response) && ($response->value);
    }
    $self->release_result($result_id) if ((defined $options{keep}) && ($options{keep} == 0));
  }
  {result_id => $result_id, hits=> $hits, first => $first };
}

sub xmlrpc_parse {
  my ($self,$content,$pathname,$overwrite) = @_;
  $overwrite = 1 unless defined $overwrite;
  my $req;
  $req = RPC::XML::request->new("parse",
          RPC::XML::base64->new($content),
          $pathname,
          $overwrite);
  $self->_process($req);
}

sub release_result {
  my ($self,$result_id) = @_;
  # We release the result set handle
  my $req = RPC::XML::request->new("releaseQueryResult", $result_id);
  $self->_process($req);
}

our $collection_uri_prefix = 'xmldb:exist://';
our $collection_root = '/db/';
our $EXTENSION_TO_MIME_TYPE = {
# Borrowing this from:
#  http://cpansearch.perl.org/src/OKAMOTO/MIME-Types-0.06/Types.pm
# and extending with the relevant ones from:
# http://www.webmaster-toolkit.com/mime-types.shtml
# UGH... eXist defaults any unknown MIME type to XML, so we should make sure
#       the TeX-y things point to octet streams, so that they become binary
# Reference: http://exist.2174344.n4.nabble.com/xmldb-store-fails-when-I-try-to-store-a-binary-resource-like-a-jpg-image-td2177579.html
# Supported MIME types:
# http://sourceforge.net/apps/trac/exist/browser/trunk/eXist/mime-types.xml.tmpl?rev=16651
	      ai => ['application/postscript', '8bit'],
	      com => ['text/plain', '8bit'],
	      dat => ['text/plain', '8bit'],
	      doc => ['application/msword', 'base64'],
	      dot => ['application/msword', 'base64'],
	      eps => ['application/postscript', '8bit'],
	      exe => ['application/octet-stream', 'base64'],
	      gif => ['image/gif', 'base64'],
	      hlp => ['text/plain', '8bit'],
	      htm => ['text/html', '8bit'],
	      html => ['text/html', '8bit'],
	      htmlx => ['text/html', '8bit'],
	      htx => ['text/html', '8bit'],
	      jpe => ['image/jpeg', 'base64'],
	      jpeg => ['image/jpeg', 'base64'],
	      jpg => ['image/jpeg', 'base64'],
        log => ['text/plain', '8bit'],
	      mpeg => ['video/mpeg', 'base64'],
	      mpe => ['video/mpeg', 'base64'],
	      mpg => ['video/mpeg', 'base64'],
	      pdf => ['application/pdf', 'base64'],
	      png => ['image/png', 'base64'],
	      ppt => ['application/vnd.ms-powerpoint', 'base64'],
	      ps => ['application/postscript', '8bit'],
	      'ps-z' => ['application/postscript', 'base64'],
	      rtf => ['application/rtf', '8bit'],
	      tex => ['application/octet-stream', '8bit'],
	      tif => ['image/tiff', 'base64'],
	      tiff => ['image/tiff', 'base64'],
	      txt => ['text/plain', '8bit'],
	      xls => ['application/vnd.ms-excel', 'base64'],
	      xml => ['application/xml', '8bit'],
	      xhtml => ['application/xhtml+xml', '8bit'],
	      zip => ['application/zip', 'base64']
};

sub already_added {
  my ($self,$d,$root)=@_;  
  my @directory_fragments = grep (length($_)>0,File::Spec->splitdir( $d ));
  my @root_fragments = grep (length($_)>0,File::Spec->splitdir( $root ));
  while (@root_fragments>1) {
    shift @directory_fragments;
    shift @root_fragments;
  }
  # 1. First, recursively create the collection path
  my $collection = $collection_uri_prefix.join('/',@directory_fragments).'/';
  # Does $collection exist? If so, do nothing and descend, otherwise create it
  my $response_bundle = $self->xmlrpc_query("xmldb:collection-exists('$collection')",keep=>0);
  return ($response_bundle->{first} eq 'true');
}

sub insert_directory {
  my ($self,$d,$root)=@_;
  #print STDERR "Insertion for $d...\n" if $self->{verbosity}>0;
  my @directory_fragments = grep (length($_)>0,File::Spec->splitdir( $d ));
  my @root_fragments = grep (length($_)>0,File::Spec->splitdir( $root ));
  while (@root_fragments>1) {
    shift @directory_fragments;
    shift @root_fragments;
  }
  # 1. First, recursively create the collection path
  my $collection = $self->make_collection(join('/',@directory_fragments).'/');
  # 2. Next, insert the source in question:
  $self->insert_files($d,$collection,$root);
  $collection;
}

sub delete_directory {
  my ($self,$d,$root)=@_;
  #print STDERR "Insertion for $d...\n" if $self->{verbosity}>0;
  my @directory_fragments = grep (length($_)>0,File::Spec->splitdir( $d ));
  my @root_fragments = grep (length($_)>0,File::Spec->splitdir( $root ));
  while (@root_fragments>1) {
    shift @directory_fragments;
    shift @root_fragments;
  }
  # Delete the collection
  $self->delete_collection($collection_root.join('/',@directory_fragments).'/');
}


sub make_collection {
  my ($self,$collection) = @_;
  my $parent_uri = $collection_uri_prefix.$collection_root;
  # Does $collection exist? If so, do nothing and descend, otherwise create it
  my $response_bundle = $self->xmlrpc_query("xmldb:collection-exists('$collection_uri_prefix$collection')",keep=>0);
  if ($response_bundle->{first} ne 'true') {
    $self->xmlrpc_query("xmldb:create-collection('$parent_uri','$collection')",keep=>0);
  }
  # Return final collection path:
  return $collection;
}

sub delete_collection {
  my ($self,$collection) = @_;
  my $parent_uri = $collection_uri_prefix.$collection_root;
  # Does $collection exist? If so, remove it, otherwise do nothing
  my $response_bundle = $self->xmlrpc_query("xmldb:collection-exists('$collection_uri_prefix$collection')",keep=>0);
  if ($response_bundle->{first} eq 'true') {
    $self->xmlrpc_query("xmldb:remove('$collection_uri_prefix$collection')",keep=>0);
  }
}

sub insert_files {
  my ($self,$d,$collection,$root) = @_;
  # Recursively insert all resources present in the directory:
  opendir (DIR,  $d);
  my @files = grep ($_ !~ /^[._]/, readdir(DIR));
  foreach (@files) {
    my ($vol,$path,$filename) = File::Spec->splitpath($_);
    if (-d "$d/$filename") {
      # 1. Directory case: recurse into subdir
      $self->insert_directory("$d/$filename",$root);
    } elsif (-f "$d/$filename") {
      # 2. File case: insert into eXist
      $filename =~ /\.(\w+)$/;
      my $extension = $1 && lc($1);
      # We need to default to octet-stream mime pipe, in order to make sure binaries are treated
      # correctly
      my $mime_type = $EXTENSION_TO_MIME_TYPE->{$extension}->[0] || 'application/octet-stream';
      # Store in $collection:
      # TODO: Something is quite fishy with paths with spaces, but the bug seems on the eXist side
      # NO SUPPORT for whitespace-containing names for now
      #my $escaped_path = join('/', map {uri_escape($_)} File::Spec->splitdir($d));
      #my $uri = "file://".$escaped_path.'/'.uri_escape($filename);
      my $uri = "file://$d/$filename";
      # TODO: Move away from anyURI, we can do this with xs:string with simply escaping single quotes !!!
      $self->xmlrpc_query("xmldb:store('$collection','$filename',xs:anyURI('$uri'),'$mime_type')",keep=>0);
      #TODO: Add check that this succeeded, provide adequate behaviour when errors occur (just DIE?)
    }
  }
}

sub insert_doc {
 my ($self,%opts) = @_;
 my ($payload,$extension,$path) = map {$opts{$_}} qw(payload extension db_pathname);
 if ($extension =~ /^xml|html|xhtml$/) {
  $self->xmlrpc_parse($payload,$path,1);
 } else {
  $path =~ /^(.+)\/[^\/]+$/;
  my $collection = $1;
  my $mime_type = $EXTENSION_TO_MIME_TYPE->{lc($extension)}->[0] || 'application/octet-stream';
  # Escaping single quotes ('):
  $payload =~ s/&/&#38;/g;
  $payload =~ s/'/&#39;/g;
  $self->xmlrpc_query("xmldb:store('$collection','$path',xs:string('$payload'),'$mime_type')",keep=>0);
 }
}

sub get_binary_doc {
  my ($self,$doc) = @_;
  my $response = $self->xmlrpc_query('util:binary-doc("'.$doc.'")');
  if ($response) {
    b($response->{first})->b64_decode;
  } else { return; }
}

# Internals, not to be exposed as methods:
# Send the request and check for errors
sub _process {
    my($self,$request) = @_;
    my $response = $self->{client}->send_request($request);
    if((!ref $response) || ($response->isa("Mojo::Exception")) || $response->is_fault) {
      my $message = "Empty response!";
      if (ref $response) {
        if ($response->isa("Mojo::Exception")) {
            $message = $response->message;
          } else {
            $message = $response->string;
          }
      }
      #TODO: Die is a bit rough, we need to do proper error-handling
      carp "An error occurred in eXist XML-RPC call: " . $message . "\n";
      return;
    }
    return $response;
}

1;

__END__

=pod 

=head1 NAME

C<CorTeX::Backend::eXist> - eXist XML DB API and driver

=head1 SYNOPSIS

    use CorTeX::Backend;
    # Class-tuning API
    $backend=CorTeX::Backend->new(exist_url=>$exist_url,verbosity=>0|1);
    $backend->exist->method

=head1 DESCRIPTION

Low-level interaction with the eXist XML DB (via XML-RPC),
together with an API layer.

Provides an abstraction layer over the tedious low-level details.

=head2 METHODS

=over 4

=item C<< $backend->exist->...

TODO add all

=back

=head1 AUTHOR

Deyan Ginev <d.ginev@jacobs-university.de>

=head1 COPYRIGHT

 Research software, produced as part of work done by 
 the KWARC group at Jacobs University Bremen.
 Released under the GNU Public License

=cut
