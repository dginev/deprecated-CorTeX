![CorTeX Framework](./public/img/logo.jpg) Framework -- Manual
======

A general purpose processing framework for **Cor**pora of **TeX** documents.

Based on your intended use of the CorTeX framework, you would find yourself in one of four workflows:
 * **[Admin workflow](#administrative-workflow)** - installing and configuring the system, adding corpora and monitoring performance
 * **[Developer workflow](#developer-workflow)** - developing and registering processing services, be they analysis, conversion or aggregation oriented.
 * **[Reviewer workflow](#reviewer-workflow)** - overseeing the current processing runs and performing quality management
 * **[Annotation workflow](#annotation-workflow)** - performing the human component of various supervised and semi-supervised tasks.

## Administrative Workflow 

### Installation

The installation process is described in detail at the [INSTALL](./INSTALL.md) documentation.

### Configuring the system components

 1. Under the administrative interface at /admin, "Configure Databases" tab:
   * Document backend - **FileSystem** OR **eXist** XML DB 
   * Task backend - **SQLite** OR **MySQL**
   * Meta backend - **Sesame**-based triple stores, **SQLite** OR **MySQL**
   
   Discussion: Currently, the safe choice is to stick with the FileSystem for a Document backend and SQLite for Task and Annotation/Meta backend.
There is support for using the eXist XML Database as a document backend and Sesame-compatible triple stores for storing annotations. However, they're not yet fully functional.
   
 2. Under the administrative interface at /admin, "Configure Workers" tab:

   Register all Gearman servers that will be used for the job distribution.

### Registering a Corpus

Under the administrative interface at /admin, "Add Corpus" tab:

 * Select an existing path at the machine running the frontend.
 * Make sure the path is read+writeable by www-data, or the user running cortex-frontend
 * The corpus needs to obey the following naming convention:

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
   i.e. each corpus entry ```foo.tex``` needs to be in a subdirectory ```foo``` named after the main TeX source. The nesting of subdirectories could go arbitrarily deep. Larger corpora would need a deeper directory structure in order not to bog down the file system. As a rule of thumb, keeping directory contents at 2000 or less files/subdirectories is a good treshold.

 * "Entry setup" - working with a corpus of single TeX files is much more efficient than one of complex TeX bundles, in terms of communication overhead. Complex setups require compression/extraction steps.
 * Overwrite - in case the import is interrupted, not specifying the overwrite option would continue from the last imported document. If specified, the import would start from scratch, completely erasing all current data, services and results associated with the corpus.

### Corpus reports

Under /corpus-report, a corpus administrator could browse through the available corpora and examine the current service reports on each registered corpus.

## Developer Workflow

CorTeX is intended as a distributed arena for processing services coming in three flavours:
 * **Converters** - map a single document D in input representation R1 (e.g. TeX) to an output representation R2 (e.g. XHTML).
 * **Analyzers** - map a single document D (or a document fragment DF, specified via XPath), in input representation R1 to a set of annotations, serialized in any major RDF format R2 (e.g. Turtle or RDF/XML).
 * **Aggregators** - map all document D (any representation) to a new resource A (any representation), where the aggregator accepts a single document on input and compositionally assembles (reduces) the annotations into the final resource A (e.g. N-gram footprint of a corpus).

Each type of service can optionally request additional prerequisite annotations and resources.

**Note:** This setup could, and indeed should, remind you of the map-reduce paradigm supported in Hadoop. The reason not to use the map-reduce paradigm directly falls beyond the scope of this manual (a hint to the differences can be seen in my [PhD proposal](https://svn.kwarc.info/repos/dginev/public/DeyanGinev_PhD_proposal.pdf), Section 3.1)

### Creating your first service 

I can't emphasize this enough -- developing a CorTeX service is **simple** and **seamless** once you grock the API. There are three aspects to keep in mind:

 * A CorTeX service is, from the distribution perspective, a **[Gearman worker](http://gearman.org/manual:workers)**
 * Each service is a **self-contained black box** that takes an input payload and returns an output payload, both of which are **JSON encoded**.
 * A CorTeX service can be written in **any** programming language with a Gearman Worker library, deployed on **any** machine connected to the internet, with **no** further requirements.

The Input-Output syntax is exhaustively specified by the following example (**JSON**):

 * Input:

   ```json
   {
      workload=>'Document content in representation R1',
      entry=>'Internal entry ID',
      service_foo_v0_1=>'RDF annotations for prerequisite service foo',
      service_bar_v0_1=>'RDF annotations for prerequisite service bar'
   }
   ```
 * Converter Output/Response:

   ```json
   {
      status=>'One of: -1 (OK) -2 (Warning), -3 (Error), -4 (Fatal)',
      log=>"Severity:category:what details\n ...", // one message per line
      document=>'Document content in representation R2'
   }
   ```

 * Analysis Output/Response:

   ```json
   {
      status=>'One of: -1 (OK) -2 (Warning), -3 (Error), -4 (Fatal)',
      log=>"Severity:category:what details\n ...", // one message per line
      annotations=>'Annotation triples in RDF representation R2'
   }
   ```

 * Aggregation Output/Response:

   *To be implemented...*

   ```json
   {
      status=>'One of: -1 (OK) -2 (Warning), -3 (Error), -4 (Fatal)',
      log=>"Severity:category:what details\n ...", // one message per line
      annotations=>'Annotation triples in RDF representation R2'
   }
   ```

As an example, consider one [analysis service](https://github.com/dginev/CorTeX-Peripheral/blob/master/lib/CorTeX/Service/mock_spotter_v0_1.pm) for counting words and sentences and its [JSON signature](https://github.com/dginev/CorTeX/blob/master/lib/CorTeX/Default/mock_spotter_v0_1.json). The JSON signature is only required for services registered in CorTeX by default, while the regular workflow goes through the developer interface, which we will cover next.

### Deploying your first Service

### Dependency Management

### Reruns and Updates

### Service reports

### Examining the data

## Reviewer workflow

*Under development...*

## Annotation workflow

*Under development...*
