package CorTeX::Util::Compare;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(set_difference same_set);

# Shallow set difference between two Perl array references
sub set_difference {
  my ($old_array,$new_array) = @_;
  $old_array //= [];
  $new_array //= [];
  my $delete=[];
  my $add = [@$new_array];
  while (@$old_array) {
    my $element = shift @$old_array;
    my @filtered_new = grep {$_ ne $element} @$add;
    if (scalar(@filtered_new) == scalar(@$add)) {
      # Not found, delete $element
      push @$delete, $element;
    } else {
      # Found, next
      $add = \@filtered_new;
    }}
  return ($delete,$add); }

sub same_set {
  my ($set1,$set2) = @_;
  $set1 //= [];
  $set2 //= [];
  my @only_set1 = @$set1;
  my @only_set2 = @$set2;
  while (@only_set1) {
    my $element = shift @only_set1;
    my @filtered_new = grep {$_ ne $element} @only_set2;
    if (scalar(@filtered_new) == scalar(@only_set2)) {
      # Not found, different sets
      return 0;
    } else {
      # Found, next
      @only_set2 = @filtered_new;
    }}
  return 0 if @only_set2;
  return 1; }
  

  1;

  __END__