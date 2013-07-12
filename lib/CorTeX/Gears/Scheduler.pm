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



1;

__END__

