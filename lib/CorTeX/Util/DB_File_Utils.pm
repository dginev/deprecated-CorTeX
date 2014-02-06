# /=====================================================================\ #
# |  MathSearch Build System                                            | #
# | DB_File Helper Utilities                                            | #
# |=====================================================================| #
# | Part of the MathSearch project: http://trac.kwarc.info/MathSearch   | #
# |  Research software, produced as part of work done by:               | #
# |  the KWARC group at Jacobs University,                              | #
# |  and Zentralblatt MATH                                              | #
# | Copyright (c) 2012                                                  | #
# | Released under the GNU Public License                               | #
# |---------------------------------------------------------------------| #
# | Deyan Ginev <d.ginev@jacobs-university.de>                  #_#     | #
# | http://kwarc.info/people/dginev                            (o o)    | #
# \=========================================================ooo==U==ooo=/ #

package CorTeX::Util::DB_File_Utils;
use warnings;
use strict;
use DB_File;
use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(db_file_connect db_file_disconnect get_db_file_field set_db_file_field); # symbols to export on request

our $CORTEX_DB_DIR = $ENV{CORTEX_DB_DIR};
($CORTEX_DB_DIR) = grep(-d $_, map("$_/CorTeX", @INC)) unless $CORTEX_DB_DIR;


sub db_file_connect {
  my ($DB_FILE_DIR) = @_;
  $DB_FILE_DIR //= $CORTEX_DB_DIR;
  # If we're running locally, the guessed path is OK,
  # but under Apache or a Linux service, the safe way is to path the file as an argument
  my $DB_FILE_PATH = "$DB_FILE_DIR/.CorTeX.cache";
  my $DB_FILE_REF = {};
  # When server is starting up, check if the DB file exists, otherwise write it with the expected
  # eXist and Sesame defaults
  tie %$DB_FILE_REF, 'DB_File', $DB_FILE_PATH, (O_RDWR|O_CREAT)
    or die "Couldn't attach DB $DB_FILE_PATH for object table: $!\n";
  return $DB_FILE_REF; }

sub db_file_disconnect {
  my ($DB_FILE_REF) = @_;
  untie %$DB_FILE_REF; }

sub get_db_file_field {
  my ($key)=@_;
  my $db_handle = db_file_connect();  
  my $val = $db_handle->{$key};
  db_file_disconnect($db_handle);
  $val; }

sub set_db_file_field {
  my ($key,$val) = @_;
  my $db_handle = db_file_connect();
  $db_handle->{$key} = $val;
  db_file_disconnect($db_handle);
  $val; }

1;
