## ![CorTeX Framework](./public/img/logo.jpg) Framework - Installation Instructions

This document covers installing the **centralized core** of the CorTeX Framework. If you are interested in developing and deploying your own CorTeX service, but not the entire framework, take a look at the [CorTeX-Peripheral](https://github.com/dginev/CorTeX-Peripheral) repository.

Brace yourselves, a lot of work to come...

For now, assuming you're running a Debian-based OS

0.1. Debian packages

```shell
sudo apt-get install gearman libfile-slurp-perl\
  mysql-server cpanminus \
  libanyevent-perl librdf-linkeddata-perl
```

0.2. CPAN dependencies (cpanm recommended)

```shell
  cpanm Mojolicious AnyEvent::Gearman Unix::Processors
```

1. Backends (optional)

  1.0. You would need Tomcat6 installed for OWLIM and eXist.
  
  ```sudo apt-get install tomcat6```

  1.1. OWLIM - Triple store (if you're **not** from Jacobs University, **please** use Sesame or request your own OWLIM access link)

    http://download.ontotext.com/owlim/3e4dc2e0-d66c-11e1-b81b-dba586cc0cc6/owlim-lite-5.2.5331.zip

    Deploy .war file in Tomcat

  1.2. eXist - XML Database
    http://sourceforge.net/projects/exist/files/Stable/1.2/eXist-1.2.6-rev9165.war/download 

    Deploy .war file in Tomcat

  1.3 MySQL - SQL Database
  
  Login as root and perform initial setup:
  
  **TODO: UPDATE ME! Section 1.3 is completely out of date**

  ```shell
   $ mysql -u root -p
   create database cortex;
   grant all on cortex.* to cortex@localhost identified by 'cortex';
   Ctrl+D
  ```

  Login as cortex and initialize database:
  
  ```shell
  $ mysql -u cortex -p
   use cortex;
   drop table if exists tasks;
   create table tasks (
    taskid INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    corpus varchar(50),
    entry varchar(200),
    service varchar(50),
    status int
  );
  create index statusidx on tasks (status);
  create index corpusidx on tasks (corpus);
  create index entryidx on tasks (entry);
  create index serviceidx on tasks (service);
  Ctrl+D
  ```

2. Configure Server settings

  2.1. Tomcat memory

    at ```/usr/share/tomcat6/bin/catalina.sh```
    after the last ```"JAVA_OPTS="``` setter, add

    ```
    JAVA_OPTS="$JAVA_OPTS -Xms3072m -Xmx3072m -XX:NewSize=512m -XX:MaxNewSize=512m
     -XX:PermSize=512m -XX:MaxPermSize=512m -XX:+DisableExplicitGC"
    ```

3. Deploying a Frontend

  **NOTE:** If you're using morbo for development, disable the watch mechanism as the SQLite database will keep changing and the server will constantly restart. Instead, run ```morbo``` as follows:

  ``` morbo -w /dev/null cortex-frontend ```

  3.1. Apache + Mod_Perl and Plack

  * Install Apache as usual

  ```$ sudo apt-get install apache2```

  * Install Mod_perl 

  ```sudo apt-get install libapache2-mod-perl2```

  * Install Plack

  ```$ sudo apt-get install libplack-perl```

  * Grant permissiosn to www-data for the webapp folder:

  ```
  $ sudo chgrp -R www-data /path/to/CorTeX
  $ sudo chmod -R g+w /path/to/CorTeX
  ```

  * Create a ```cortex``` VirtualHost file in
   
    ```/etc/apache2/sites-available/``` and ```/etc/apache2/sites-enabled/```:
 
  ```
  <VirtualHost *:80>
    ServerName cortex.example.com 
    DocumentRoot /path/to/CorTeX
    Header set Access-Control-Allow-Origin *                                    

    PerlOptions +Parent
                                                              
    <Perl>
      $ENV{PLACK_ENV} = 'production';
      $ENV{MOJO_HOME} = '/path/to/CorTeX';
    </Perl>

    <Location />
      SetHandler perl-script
      PerlHandler Plack::Handler::Apache2
      PerlSetVar psgi_app /path/to/CorTeX/cortex-frontend
    </Location>

    ErrorLog /var/log/apache2/cortex.error.log
    LogLevel warn
    CustomLog /var/log/apache2/cortex.access.log combined
  </VirtualHost>
  ```