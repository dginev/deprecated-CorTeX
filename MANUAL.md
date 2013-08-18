![CorTeX Framework](./public/img/logo.jpg) Framework -- Manual
======

A general purpose processing framework for **Cor**pora of **TeX** documents.

Based on your intended use of the CorTeX framework, you would find yourself in one of three workflows:
 * **Admin workflow** - installing and configuring the system, adding corpora and monitoring performance
 * **Developer workflow** - developing and registering processing services, be they analysis, conversion or aggregation oriented.
 * **Reviewer workflow** - overseeing the current processing runs and performing quality management
 * **Annotation workflow** - performing the human component of various supervised and semi-supervised tasks.

## Administrative Workflow 

### Installation

The installation process is described in detail at the [INSTALL](./INSTALL.md) documentation.

### Configuring the system components

1. Under the administrative interface at /admin, "Configure Databases" tab:

 * Document backend - FileSystem OR eXist XML DB 
 * Task backend - SQLite or MySQL
 * Meta backend - Sesame-based triple stores, SQLite or MySQL

Discussion: Currently, the safe choice is to stick with the FileSystem for a Document backend and SQLite for Task and Annotation/Meta backend.
There is support for using the eXist XML Database as a document backend and Sesame-compatible triple stores for storing annotations. However, they're not yet fully functional.

2. Under the administrative interface at /admin, "Configure Workers" tab:

Register all Gearman servers that will be used for the job distribution.

### Registering a Corpus

Under the administrative interface at /admin, "Add Corpus" tab:

 * Select an existing path at the File System where the frontend is running.
 * The corpus needs to follow the following naming convention:
 ```
  /corpus
         /foo
             /foo.tex
         /bar
             /bar.tex
         ...
         /baz
             /foobar
                    /foobar.tex
 ```
   i.e. each corpus entry ```foo.tex``` needs to be in a subdirectory ```foo``` named after the main TeX source.
 * "Entry setup" - working with a corpus of single TeX files is much more efficient than one of complex TeX bundles
 * Overwrite - in case the import is interrupted, not specifying the overwrite option would continue from the last imported document. If specified, the import would start from scratch.

### Corpus reports



## Developer Workflow

### Deploying your first Service

### Dependency Management

### Reruns and Updates

### Service reports

### Examining the data

## Reviewer workflow

## Annotation workflow
