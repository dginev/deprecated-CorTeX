![CorTeX Framework](./public/img/logo.jpg) Framework -- Manual
======

A general purpose processing framework for **Cor**pora of **TeX** documents.

Based on your intended use of the CorTeX framework, you would find yourself in one of four workflows:
 * **[Admin workflow](#administrative-workflow)** - installing and configuring the system, adding corpora and monitoring performance
 * **[Developer workflow](#developer-workflow)** - developing and registering processing services, be they analysis, conversion or aggregation oriented.
 * **[Reviewer workflow](#reviewer-workflow)** - overseeing the current processing runs and performing quality management
 * **[Annotation workflow](#annotation-workflow)** - performing the human component of various supervised and semi-supervised tasks.

## Table of Contents
<ul>
  <li><a href="#administrative-workflow">Administrative Workflow</a>
  <ul>
    <li><a href="#installation">Installation</a></li>
    <li><a href="#configuring-the-system-components">Configuring the system components</a></li>
    <li><a href="#registering-a-corpus">Registering a Corpus</a></li>
    <li><a href="#corpus-reports">Corpus reports</a></li>
  </ul></li>
  <li><a href="#developer-workflow">Developer Workflow</a>
  <ul>
    <li><a href="#creating-your-first-service">Creating your first service</a></li>
    <li><a href="#deploying-your-first-service">Deploying your first Service</a></li>
    <li><a href="#dependency-management">Dependency Management</a>
    <ul>
      <li><a href="#why-do-we-need-dependencies">Why do we need Dependencies?</a></li>
      <li><a href="#adding-dependencies-to-your-service">Adding dependencies to your service</a></li>
    </ul></li>
    <li><a href="#reports-and-reruns">Reports and Reruns</a></li>
  </ul></li>
  <li><a href="#reviewer-workflow">Reviewer workflow</a></li>
  <li><a href="#annotation-workflow">Annotation workflow</a></li>
</ul>

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

Developing a CorTeX service is **simple** and **seamless** once you grock the API. There are three aspects to keep in mind:

 * A CorTeX service is, from the distribution perspective, a **[Gearman worker](http://gearman.org/manual:workers)**
 * Each service is a **self-contained black box** that takes an input payload and returns an output payload, both of which are **JSON encoded**.
 * A CorTeX service can be written in **any** programming language with a Gearman Worker library, deployed on **any** machine connected to the internet, with **no** further requirements.

If you decide to author your service in Perl, consider forking and building on top of the [CorTeX-Peripheral](https://github.com/dginev/CorTeX-Peripheral) repository. It provides a **CorTeX::Service** template class that abstracts away the nitty-gritty details of the Gearman network communication. Combined with the **cortex-spawner** service, deploying a custom service on a new machine becomes completely automatic.

The Input-Output syntax is exhaustively specified by the following example (**JSON**):

 * Input:

   ```json
   {
      "workload":"Document content in representation R1",
      "entry":"Internal entry ID",
      "service_foo_v0_1":"RDF annotations for prerequisite service foo",
      "service_bar_v0_1":"RDF annotations for prerequisite service bar"
   }
   ```
 * Converter Output/Response:

   ```json
   {
      "status":"One of: -1 (OK) -2 (Warning), -3 (Error), -4 (Fatal)",
      "log":"Severity:category:what details\n ...",
      "document":"Document content in representation R2"
   }
   ```

 * Analysis Output/Response:

   ```json
   {
      "status":"One of: -1 (OK) -2 (Warning), -3 (Error), -4 (Fatal)",
      "log":"Severity:category:what details\n ...",
      "annotations":"Annotation triples in RDF representation R2"
   }
   ```

 * Aggregation Output/Response:

   *To be implemented...*

   ```json
   {
      "status":"One of: -1 (OK) -2 (Warning), -3 (Error), -4 (Fatal)",
      "log":"Severity:category:what details\n ...",
      "annotations":"Annotation triples in RDF representation R2"
   }
   ```

The "log" field is essential for leveraging the automated reports of CorTeX. The "log" string should contain a single message per line in the above form, which are automatically parsed and catalogued by the server. Making use of the log field will allow you to recognise the most prominent **bugs** of your service, as well as to conveniently mark the relevant entries for **rerun**, once a problem has been patched.

As an example, consider one [analysis service](https://github.com/dginev/CorTeX-Peripheral/blob/master/lib/CorTeX/Service/mock_spotter_v0_1.pm) for counting words and sentences and its [JSON signature](https://github.com/dginev/CorTeX/blob/master/lib/CorTeX/Default/mock_spotter_v0_1.json). The JSON signature is only required for services registered in CorTeX by default, while the regular workflow goes through the developer interface, which we will cover next.

### Deploying your first Service

Now that you have your Gearman worker compliant with the CorTeX API, you're ready to get cracking.

The developer interface, under '/dev', allows you to first register and later update your service:
 
  * The **name** and **version** fields are used to create a unique identifier for your service within CorTeX
  * In case you prefer to use your own Gearman server, you can specify it in the **URL** field
  * You must always specify the **type** of your service - conversion, analysis or aggregation.
  * Once you have chosen the type, you would need to specify the **formats** expected on input and output. The input format must be already known to the system as produced by one of the registered converters.
  * For analyses and aggregation services, you can optionally specify an XPath expression that will send only relevant document fragments, rather than entire documents.
  * For aggregation services, a name is needed for the resource created by the service (e.g. 2-Grams.xml)
  * [Dependency management](#dependency-management) deserves more detailed attention and we will cover it separately.
  * You can choose which **corpora** your service is to be enabled on before finally registering it.

Don't worry about getting some of the fields wrong at first, you are always free to come back and update the service signature later on.

Once you've hit "Add Service" and a confirmation message is displayed, CorTeX will start queueing jobs in Gearman addressed to your service, so whenever you start your Gearman worker it will get served one job per document (fragment) for each corpus that it has been enabled on.

Congratulations, you have registered your first CorTeX service! 

### Dependency Management

#### Why do we need Dependencies?

All initially imported corpora into the framework are collections of TeX documents. However, TeX is notoriously hard to process and parse and is not suited for automated analysis or rendering inside the browser. We find that different representations are good in serving different purposes, e.g. XHTML for parseability and native browser rendering, OMDoc for exposing the structural semantics of a document, Daisy to make documents accessible, etc. This briefly motivates the need for different conversion services. Sometimes, the conversion would not take the TeX source as input but the result of a previous conversion service, e.g. an ePub service could directly build on top of XHTML.

The need for building on top of previous results is even more dramatic when it comes to analysis services. In traditional NLP there is a well-established sequence of ever increasing semanticization of a document, first exposing the syntax (e.g. tokenization, parts of speech), then shallow semantics (e.g. named entities, sentiment annotations) and finally deep semantics (e.g. logical forms of sentences, anaphora resolution, textual entailment).

Certainly, a **dynamic programming** intuition is the most efficient one in such a setup - each step of such a pipeline would save its own results (final for some applications, intermediate for others), and a subsequent service could start where the previous step stopped. For example, a named-entity recognition service would depend on the document being converted to a parseable representation (e.g. XHTML), and then tokenized (words and sentence boundaries). More exotically, a converter that targets the OMDoc format, would depend on an array of analysis services (e.g. annotations for definitions, axioms, proofs), the stand-off results of which would be aggregated together into a semantic XML representation.

#### Adding CorTeX dependencies to your service

Adding/removing dependencies for your application is easy to realize with the developer interface under '/dev'.

The one mandatory dependency is the previous conversion service on which the current service is based. If you want to process the original TeX, choose the "import" service, otherwise select the service that generates your representation of choice. For most linguistic analysis purposes the official default recommendation is using the "TeX to TEI XHTML" as your conversion basis. As the name suggests, your input would then consist of a word- and sentence-tokenized XHTML document.

The document created by the "Conversion" dependency will be available on input in the "workload" field of the JSON payload.

Selecting prerequisite "Analyses" and "Resources" is optional, but when selected the data will be available on input in a field named after the unique identifier of the prerequisite service, as shown in [the API example](#creating-your-first-service).

Details to keep in mind:
 * You need to manually enable all prerequisites to be active on the corpus/corpora your service is enabled on, if they aren't enabled already. You can achieve that from the "Update Service" tab in the '/dev' interface.
 * Upon updating the dependencies, all completed jobs will be queued for reconversion and the results will be lost.
 * If a prerequisite service is not yet completed, or has completed with regular or fatal errors, the document it was processing will remain blocked for your service, until all prerequisites pass cleanly or only with warnings.
 * Queueing any selection of documents for rerun will trigger a rerun for all services that depend on your service.

#### Adding External depdendencies

TODO: Discuss managing external dependencies. Generally it's beyond the scope of CorTeX as a framework and should be managed by the particular service project (and automated on deployments). One example is the pair of CorTeX-Peripheral and the KWARC deployments.

### Reports and Reruns

The development of an analysis service only really starts after the service has been deployed and meets the real-world data of large-scale TeX corpora. There are several tools designed to help you spot prominent problems with your service, as long as you use the messaging conventions.

 * Under '/service-report' you can select your service and get a high-level overview of all enabled corpora.
 * Clicking on a corpus name of interest, you get a detailed report for the chosen corpus-server pair.
 * In the detailed report, each message class is expandable and provides frequency statistics on severity, message category and message component.
 * Zooming in the message component level redirects to a file browser, that allows you to inspect individual jobs - their **input** documents, **output** documents, annotations or resources, as well as the entire **log** of the job.

At each level of magnification in the detailed report screen and the file browser, you have the opportunity to mark a selection of the documents as **queued for rerun**, providing a *diagnose-patch-test* workflow for debugging and development.

## Reviewer workflow

*Under development...*

## Annotation workflow

*Under development...*
