# /=====================================================================\ #
# |  CorTeX Framework                                                   | #
# | System Scheduler - Singleton Class                                  | #
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
package CorTeX::Gears::Scheduler;

# We order all registered modules M into a processing queue, based on dependency prerequisites
# In order to have a meaningful way to deal with errors and updates, queue won't be linear but a DAG
# For example:

# Import <- Build <- NGrams      <- NER   <|
#                 <- MathParser           <|-- Definition Spotter 


# Dependency modeling:
# If a service S, tasked to run on an entry E in corpus C, depends on N prerequisite services,
# we mark the status of (C,E,S) as -N

# Say SP is a prerequisite service for S. Upon the completion of (C,E,SP), the Scheduler is responsible to 
# increment with one the status of (C,E,S). As the prerequisite services are completed, the task (C,E,S) approaches status 0
# which is the code for "ready for processing".

# With this scheme, it is crucial that upon any status change of (C,E,SP) - be it rerun, deletion, or else, there is a need to propagate
# the change to any task enabled by the completion of (C,E,SP), back to -N.

# For this purpose we keep two Global hash maps, pointing in both directions of "dependency" and "enables".
# As we have a number of parallel schedulers, these Global hash maps need to be accessible to all of them and are hence
# stored in the Job store, under table "dependencies". (Think of updates to these tables, e.g. upon module updates/deletions)

# As modules explicitly specify the dependency direction, that would be easy to update on change.
# The enables direction is automatically computed and would hence require special logic.
# - For each of the old "enables" entries, update them to remove a deleted service
# - For each of the new "dependency" entries, update their "enables" rows to include a new service

# How do we keep sync between the MySQL store and the parallel schedulers?

1;

__END__

 