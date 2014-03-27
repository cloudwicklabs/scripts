Cloudwick Deployment Scripts
============================
DSE Installer (dse_install.sh)
------------------------------
Script used to install cassandra datastax enterprise edition.

###Variables:
Change the following variables `datastax_user` & `datastax_password` in the script to match your datastax enterprise credentials.

###Usage:

```
curl -sO https://raw2.github.com/cloudwicklabs/scripts/master/dse_install.sh
chmod +x dse_install.sh
./dse_install.sh -h
```

Sample help usage:

```
Syntax
dse_install.sh -s -a -d -B [IPv4] -j -J {512M|1G} -N {200M|1G} -h

-s: start dse-solr on this machine
-a: start dse-hadoop analytics on this machine
-d: configure datacenter replication
-j: configure cassandra jvm heap size
-b: attempt to find the broadcast address (use this for virtual instances like aws)
-r: force restart the dse daemon
-i: increase timeout's and default's for write request, read request, rpc request, concurrent writes, memtable flush writes
-S: seeds list to use (example: s1.ex.com,s2.ex.com)
-B: broadcast address to use
-J: cassandra jvm size (default: 4G)
-N: cassandra jvm heap new generation size (default: 800M)
-D: datacenter name to use (default: DC1)
-R: rack name to use (default: RAC1)
-h: show help

Examples:
Install dse cassandra on a single machine:
dse_install.sh

Install dse on a cluster with seeds list:
dse_install.sh -S "s1.ex.com,s2.ex.com"

Install dse on a cluster with seeds list, configure jvm heap sizes:
dse_install.sh -S "s1.ex.com,s2.ex.com" -j -J 8G -N 1G
```

Puppet Installer (puppet_install.sh)
------------------------------------
Script to install puppet server/client, additionally can do the following:

* puppetdb for stored configs
* passenger for scaling puppet server
* postgresql (dependency for puppetdb)
* autosigning for puppet clients belonging to same domain

###Usage:

```
curl -sO https://raw2.github.com/cloudwicklabs/scripts/master/puppet_install.sh
chmod +x puppet_install.sh
./puppet_install.sh -h
```

Sample help usage:

```
Syntax
install_puppet.sh -s -c -d -p -a -j -J {-Xmx512m|-Xmx256m} -P {psql_password} -H {ps_hostname} -h

-s: puppet server setup
-c: puppet client setup
-d: setup puppetdb for stored configurations
-p: install and configure passenger which runs puppet master as a rack application inside apache
-a: set up auto signing for the same clients belonging to same domain
-j: set up cron job for running puppet agent every 30 minutes
-J: JVM Heap Size for puppetdb
-P: postgresql password for puppetdb|postgres user
-H: puppet server hostname (required for client setup)
-h: show help

Examples:
Install puppet server with all defaults:
install_puppet.sh -s
Install puppet server with puppetdb and passenger:
install_puppet.sh -s -p -d
Install puppet client:
install_puppet.sh -c -H {puppet_server_hostname}
```

Chef Installer (chef_install.sh)
------------------------------------
Script to install chef server/client and configure knife.

###Usage:

```
curl -sO https://raw2.github.com/cloudwicklabs/scripts/master/chef_install.sh
chmod +x chef_install.sh
./chef_install.sh -h
```

Sample help usage:

```
Syntax
chef_install.sh -s -c -w -J {-Xmx512m|-Xmx256m} -H {cs_hostname} -h

-s: chef server setup
-c: chef client setup
-w: Chef workstation setup
-J: JVM Heap Size for solr
-H: chef server ip (required for chef client setup)
-h: show help
```

Mongo Installer (mongo_install.sh)
----------------------------------
Script to install mongo in single/sharded/replicated mode with support for deploying mms-agent with munin hardware monitoring

###Usage:

```
curl -sO https://raw2.github.com/cloudwicklabs/scripts/master/mongo_install.sh
chmod +x mongo_install.sh
./mongo_install.sh -h
```

Sample help usage and examples:

```
Syntax
mongo_install.sh OPTS

where OPTS are:
-l: start mongo router instance (load balancer)
-d: configure single mongod instance
-s: configure as shard server
-c: configure mongo config server
-m: install and configure mms agent
-R: name of the replica set
-S: master | slave replica set configuration
-C: config DB (list of config servers)
-M: replica set members (rs1:27018,rs2:27018,rs3:27018)
-b: bind to eth0 ip address (default: listen on all interfaces)
-I: initialize replica set with given members list (run this from replica primary)
-A: specify the arbiter node while initializing replica set
-K: mms api key
-v: verbose output
-h: show help

Examples:
Install mongo on a single machine:
mongo_install.sh -d

Install mongo on a cluster mode with 2 replica sets:
1. Start mongo router instance
  mongo_install.sh -l -C host1:27019,host2:27019,host3:27019
2. Start mongo replica server master (s1r1.cw.com)
  mongo_install.sh -s -R replA -S master
3. Start mongo replica server slave (s1r2.cw.com)
  mongo_install.sh -s -R replA -S slave
4. Start mongo arbiter server (s1a1.cw.com)
  mongo_install.sh -s -R replA -a
5. Start mongo replica server master (s2r1.cw.com)
  mongo_install.sh -s -R replB -S master
6. Start mongo replica server slave (s2r2.cw.com)
  mongo_install.sh -s -R replB -S slave
7. Start mongo arbiter server (s2a1.cw.com)
  mongo_install.sh -s -a -R replB
8. Start config server1
  mongo_install.sh -c
9. Start config server2
  mongo_install.sh -c
10. Start config server3
  mongo_install.sh -c
11. Initialize replica set 1, run this from replica (replA) primary master
  mongo_install.sh -I "s1r1.cw.com:27018,s1r2.cw.com:27018,s1a1.cw.com:27018" -A "s1a1.cw.com:27018"
12. Initialize replica set 2, run this from replica (replB) primary master
  mongo_install.sh -I "s2r1.cw.com:27018,s2r2.cw.com:27018,s2a1.cw.com:27018" -A "s2a1.cw.com:27018"

```

Job Postings Fetcher (fetch_job_postings.rb)
--------------------------------------------
Script to pull job postings from dice and put them to google spread sheet

###Usage:

Download:

```
curl -sO https://raw2.github.com/cloudwicklabs/scripts/master/fetch_job_postings.rb
```

Install ruby gem dependencies:

```
gem install json parallel google_drive --no-ri --no-rdoc
```

Usage:

1. Encrypt the google password (entering the following command will ask for password
  in hidden string format and also asks for a hash salt used to encrypt password):

  ```
  ruby fetch_job_postings.rb -e
  ```

2. Using the above encrypted password and salt you can pull the job postings from dice
  and put them to google spreadsheet:

  ```
  ruby fetch_job_postings.rb --search java --age-of-postings 1 \
    --traverse-depth 1 --page-search CON_CORP \
    --spreadsheet-name job_postings_bot --username test@gmail.com \
    --password [ENCRYPTED_PASSWORD] --hash [HASH_SALT]
  ```

For description on options:

```
ruby fetch_job_postings.rb --help
```

###License and Authors

Authors: [Ashrith](http://github.com/ashrithr)

Apache 2.0. Please see `LICENSE.txt`. All contents copyright (c) 2013, Cloudwick Labs.
