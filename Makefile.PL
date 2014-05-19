#======================================================================
# Makefile Maker for CorTeX-Peripherals
# d.ginev@jacobs-university.de
#======================================================================
use ExtUtils::MakeMaker;
use strict;
use warnings;
use File::Basename 'dirname';
use File::Spec::Functions 'catdir';

#======================================================================
# Use "perl Makefile.PL <options>"
#======================================================================
our @EXCLUSIONS=();
our $MORE_MACROS = {};
our $MORE_MAKERULES=''; 

install_spawner_service();
WriteMakefile(
	NAME => 'CorTeX',
	AUTHOR => 'Deyan Ginev <d.ginev@jacobs-university.de>',
	ABSTRACT => "Job Server and Frontend for the CorTeX framework",
	VERSION_FROM => 'bin/cortex-frontend',
	PREREQ_PM => { 
		"XML::LibXML"=>0,
		"AnyEvent::Gearman"=>0,
		"Unix::Processors"=>0,
		"HTML::Entities"=>0,
		"File::Spec"=>0,
		"Mojolicious"=>0,
		"URI::Escape"=>0,
		"DB_File"=>0,
		"DBI"=>0,
		"RDF::Trine"=>0,
		"Scalar::Util"=>0,
		"XML::Simple"=>0,
		"File::Slurp"=>0,
		"File::Path"=>0,
		"RPC::XML"=>0,
		"JSON::XS"=>0,
		"AnyEvent::Gearman"=>0,
    "List::Util"=>0,
    "List::MoreUtils"=>0
	},
	EXE_FILES => ['bin/cortex-gears','bin/cortex-client','bin/cortex-frontend'],
	macro => $MORE_MACROS,
);

#**********************************************************************
# Overriding ExtUtils::MM methods
#**********************************************************************
# Append any additional Makefile rules added by the following.
# Exclude the sources used to generate others from the build (See below).
sub MY::libscan {
	my($self,$path)=@_;
	if(($path =~ /~$/) || grep($path eq $_, @EXCLUSIONS)){
		return ""; }
	$self->MY::SUPER::libscan($path); }
sub MY::postamble {
	shift->MY::SUPER::postamble(@_) . $MORE_MAKERULES; }

sub install_spawner_service {
	push(@EXCLUSIONS,'blib/script/cortex-job-server');
	push(@EXCLUSIONS,'blib/lib/CorTeX/TaskDB.db');
	push(@EXCLUSIONS,'blib/lib/CorTeX/MetaDB.db');
	push(@EXCLUSIONS,'blib/lib/CorTeX/MetaDB.db');
	push(@EXCLUSIONS,'blib/lib/CorTeX/.CorTeX.cache');

    my $FILE_BASE = dirname(__FILE__);
	my $db_dir = File::Spec->rel2abs(catdir($FILE_BASE,"lib","CorTeX"));
	$$MORE_MACROS{RECORD_DBDIR} = '$(PERLRUN) -pe \'s@\#__CORTEX_DB_DIR__@CORTEX_DB_DIR="'.$db_dir.'"@\'';

	$MORE_MAKERULES .= <<'InstallService';
# Copy the spawner service to /etc/init.d/
pure_install :: $(INST_SCRIPT)/cortex-job-server

$(INST_SCRIPT)/cortex-job-server: bin/cortex-job-server
	$(RECORD_DBDIR) bin/cortex-job-server > $(INST_SCRIPT)/cortex-job-server
	chmod +x $(INST_SCRIPT)/cortex-job-server
	$(MV) $(INST_SCRIPT)/cortex-job-server /etc/init.d/
InstallService
}