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


###License and Authors

Authors: [Ashrith](http://github.com/ashrithr)

Apache 2.0. Please see `LICENSE.txt`. All contents copyright (c) 2013, Cloudwick Labs.