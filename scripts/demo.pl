use lib "../lib";
use BuildSystem::Import;

my $exist_url = "http://guest:guest\@localhost:8080/eXist-1.2.6-rev9165/xmlrpc";
my $sesame_url = "http://localhost:8080/openrdf-sesame";

# arXiv:
# my $importer = BuildSystem::Import->new(root=>'/media/MyPassport/arXiv/arxiv',verbosity=>1, upper_bound=>1000,exist_url=>$exist_url);

# ZBL:
my $importer = BuildSystem::Import->new(root=>'/home/dreamweaver/svn/MathSearch/src/ZBL-corpus',verbosity=>1, upper_bound=>10,exist_url=>$exist_url,sesame_url=>$sesame_url);

$importer->process_all;
