#!/bin/bash
#
# Author:: Ashrith Mekala (<ashrith@cloudwick.com>)
# Description:: Script to install DSE Cassandra
# Version:: 0.3
# Supported OS:: Redhat/CentOS (5 & 6), Ubuntu (precise & lucid)
#
# Copyright 2013, Cloudwick, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

####
## Run-time Variables (you'll have to change these)
####
# dse credentials
datastax_user=""
datastax_password=""

# where cassandra stores data
cassandra_data_dirs=( "/cassandra/data" )
cassandra_commit_log_dir="/cassandra/commitlog"
cassandra_saved_caches_dir="/cassandra/saved_caches"

# where spark stores (caches) rdd's, export SPARK_RDD_DIR="/var/lib/spark/rdd"
spark_rdd_dirs="/var/lib/spark/rdd"

# name of the cluster
cassandra_cluster_name="Test Cluster"

####
## Configuration Variables (change these, only if you know what you are doing)
####
# dse version to install, http://www.datastax.com/download/enterprise/versions
dse_version="4.6.0"

#####
## !!! DONT CHANGE BEYOND THIS POINT. DOING SO MAY BREAK THE SCRIPT !!!
#####

####
## Global Variables (script-use only)
####
# os specific variables
declare os
declare os_str
declare os_version
declare os_codename
declare os_arch
declare package_manager

# colors
clr_blue="\x1b[34m"
clr_green="\x1b[32m"
clr_yellow="\x1b[33m"
clr_red="\x1b[31m"
clr_cyan="\x1b[36m"
clr_end="\x1b[0m"

# log files
stdout_log="/tmp/$(basename $0).stdout"
stderr_log="/tmp/$(basename $0).stderr"

# pre-req commands, will be installed if not already present
pre_req_cmds=( "curl" "vim" )

####
## Utility functions
####

function print_banner () {
    echo -e "${clr_blue}
        __                __         _      __
  _____/ /___  __  ______/ /      __(_)____/ /__
 / ___/ / __ \/ / / / __  / | /| / / / ___/ //_/
/ /__/ / /_/ / /_/ / /_/ /| |/ |/ / / /__/ ,<
\___/_/\____/\__,_/\__,_/ |__/|__/_/\___/_/|_| ${clr_green} Cloudwick Labs.  ${clr_end}\n"

  print_info "Logging enabled, check '${clr_cyan}${stdout_log}${clr_end}' and '${clr_cyan}${stderr_log}${clr_end}' for respective output."
}

function print_error () {
  printf "$(date +%s) ${clr_red}[ERROR] ${clr_end}$@\n"
}

function print_warning () {
  printf "$(date +%s) ${clr_yellow}[WARN] ${clr_end}$@\n"
}

function print_info () {
  printf "$(date +%s) ${clr_green}[INFO] ${clr_end}$@\n"
}

function print_debug () {
  if [[ $debug = "true" ]]; then
    printf "$(date +%s) ${clr_cyan}[DEBUG] ${clr_end}$@\n"
  fi
}

function execute () {
  local full_redirect="1>>$stdout_log 2>>$stderr_log"
  /bin/bash -c "$@ $full_redirect"
  ret=$?
  if [ $ret -ne 0 ]; then
    print_debug "Executed command \'$@\', returned non-zero code: ${clr_yellow}${ret}${clr_end}"
  else
    print_debug "Executed command \'$@\', returned successfully."
  fi
  return $ret
}

function check_for_root () {
  if [ "$(id -u)" != "0" ]; then
   print_error "Please run with super user privileges."
   exit 1
  fi
}

function get_system_info () {
  print_debug "Collecting system configuration..."

  os=`uname -s`
  if [[ "$os" = "SunOS" ]] ; then
    os="Solaris"
    os_arch=`uname -p`
  elif [[ "$os" = "Linux" ]] ; then
    if [[ -f /etc/redhat-release ]]; then
      os_str=$( cat `ls /etc/*release | grep "redhat\|SuSE"` | head -1 | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } print $i; } }' | tr '[:upper:]' '[:lower:]' )
      os_version=$( cat `ls /etc/*release | grep "redhat\|SuSE"` | head -1 | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } } }' | tr '[:upper:]' '[:lower:]')
      if [[ $os_str =~ centos ]]; then
        os="centos"
      elif [[ $os_str =~ red ]]; then
        os="redhat"
      else
        print_error "OS: $os_str is not yet supported, contact support@cloudwicklabs.com"
        exit 1
      fi
    elif [[ -f /etc/lsb-release ]] ; then
      os_str=$( lsb_release -sd | tr '[:upper:]' '[:lower:]' | tr '"' ' ' | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } print $i; } }' )
      os_version=$( lsb_release -sd | tr '[:upper:]' '[:lower:]' | tr '"' ' ' | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } } }')
      if [[ $os_str =~ ubuntu ]]; then
        os="ubuntu"
        if grep -q precise /etc/lsb-release; then
          os_codename="precise"
        elif grep -q lucid /etc/lsb-release; then
          os_codename="lucid"
        else
          print_error "Sorry, only precise & lucid systems are supported by this script. Exiting."
          exit 1
        fi
      else
        print_error "OS: $os_str is not yet supported, contact support@cloudwicklabs.com"
        exit 1
      fi
    else
      print_error "OS: $os_str is not yet supported, contact support@cloudwicklabs.com"
      exit 1
    fi
    os=$( echo $os | sed -e "s/ *//g")
    os_arch=`uname -m`
    if [[ "xi686" == "x${os_arch}" || "xi386" == "x${os_arch}" ]]; then
      os_arch="i386"
    fi
    if [[ "xx86_64" == "x${os_arch}" || "xamd64" == "x${os_arch}" ]]; then
      os_arch="x86_64"
    fi
  elif [[ "$os" = "Darwin" ]]; then
    type -p sw_vers &>/dev/null
    [[ $? -eq 0 ]] && {
      os="macosx"
      os_version=`sw_vers | grep 'ProductVersion' | cut -f 2`
    } || {
      os="macosx"
    }
  fi

  if [[ $os =~ centos || $os =~ redhat ]]; then
    package_manager="yum"
  elif [[ $os =~ ubuntu ]]; then
    package_manager="apt-get"
  else
    print_error "Unsupported package manager. Please contact support@cloudwicklabs.com."
    exit 1
  fi

  print_debug "Detected OS: ${os}, Ver: ${os_version}, Arch: ${os_arch}"
}

####
## Script specific functions
####

function check_preqs () {
  check_for_root
  print_info "Checking your system prerequisites..."

  # Install required commands (if not found)
  for command in "${pre_req_cmds[@]}"; do
    type -P $command &> /dev/null || {
      print_warning "Command $command not found"
      print_info "Attempting to install $command..."
      execute "${package_manager} -y install $command"
      if [[ $? -ne 0 ]]; then
        print_warning "Could not install $command. This may cause issues."
      fi
    }
  done
}

function add_datastax_repo () {
  case "$os" in
    centos|redhat)
      if [[ ! -f /etc/yum.repos.d/datastax.repo ]]; then
        print_info "Adding datastax repo to yum repositories list..."
        cat > /etc/yum.repos.d/datastax.repo <<EOF
[datastax]
name=DataStax Repo for Apache Cassandra
baseurl=http://${datastax_user}:${datastax_password}@rpm.datastax.com/enterprise
enabled=1
gpgcheck=0
EOF
      fi
      ;;
    ubuntu)
      if [[ ! -f /etc/apt/sources.list.d/datastax.sources.list ]]; then
        print_info "Adding datastax repo to apt sources list"
        execute "echo \"deb http://${datastax_user}:${datastax_password}@debian.datastax.com/enterprise stable main\" | tee -a /etc/apt/sources.list.d/datastax.sources.list"
        print_info "Adding datastax repo to apt trusted list"
        execute "curl -sL https://debian.datastax.com/debian/repo_key | sudo apt-key add -"
        print_info "Refreshing apt packages list..."
        execute "sudo apt-get update"
      fi
      ;;
    *)
      print_error "$os is not yet supported, please contact support@cloudwicklabs.com."
      exit 1
      ;;
  esac
}

function install_oracle_jdk () {
  cd /opt
  if [[ $os_arch == "x86_64" ]]; then
    local download_url="http://download.oracle.com/otn-pub/java/jdk/7u45-b18/jdk-7u45-linux-x64.tar.gz"
  else
    local download_url="http://download.oracle.com/otn-pub/java/jdk/7u45-b18/jdk-7u45-linux-i586.tar.gz"
  fi
  local download_file=$(echo $download_url | awk -F'/' '{print $NF}')
  local download_dir="jdk1.7.0_45"

  if [[ ! -d $download_dir ]]; then
    print_info "Attempting to download JDK ..."
    execute "wget --no-check-certificate --no-cookies --header \"Cookie: oraclelicense=accept-securebackup-cookie\" ${download_url} -O ${download_file}"
    if [[ $? -eq 0 ]]; then
      print_info "Sucessfully downloaded Oracle JDK."
      execute "tar xzf $download_file"
      execute "ln -s $download_dir java"
    else
      echo "Failed downloading JAVA!"
      exit 1
    fi
  fi
}

function configure_jdk () {
  install_oracle_jdk
  local java_profile="/etc/profile.d/java_home.sh"
  if [[ ! -f $java_profile ]]; then
    print_info "Configuring java home and path variables"
    cat > $java_profile <<\EOF
export JAVA_HOME=/opt/java
export PATH=$JAVA_HOME/bin:$PATH
export JRE_HOME=/opt/java
EOF
    source $java_profile
  elif [[ ! -x $java_profile ]]; then
    chmod +x $java_profile && source $java_profile
  else
    source $java_profile
  fi
}

function stop_iptables () {
  case "$os" in
    centos|redhat)
      print_info "Stopping ip tables..."
      execute "service iptables stop"
      execute "chkconfig iptables off"
      ;;
    ubuntu)
      print_info "Disabling ufw..."
      execute "ufw disable"
      ;;
    *)
      print_error "$os is not supported yet."
      exit 1
      ;;
  esac
}

function stop_selinux () {
  if [[ -f /etc/selinux/config ]]; then
    print_info "Disabling selinux..."
    execute "/usr/sbin/setenforce 0"
    execute "sed -i.old s/SELINUX=enforcing/SELINUX=disabled/ /etc/selinux/config"
  fi
}

function check_if_dse_is_installed () {
  print_info "Checking to see if dse is installed..."
  case "$os" in
    centos|redhat)
      execute "rpm -q dse-full"
      return $?
      ;;
    ubuntu)
      execute "dpkg --list | grep dse-full"
      return $?
      ;;
    *)
      print_error "$os is not supported yet."
      exit 1
      ;;
  esac
}

function install_dse () {
  check_if_dse_is_installed
  if [[ $? -eq 0 ]]; then
    print_info "Package dse-$dse_version is already installed. Skipping installation step."
    return
  fi
  add_datastax_repo
  print_info "Installing dse-${dse_version}..."
  case "$os" in
    centos|redhat)
      execute "$package_manager install -y dse-full-$dse_version-1"
      if [[ $? -ne 0 ]]; then
        print_error "Failed installing dse, stopping."
        exit 1
      fi
      ;;
    ubuntu)
      execute "$package_manager install -y dse-full=$dse_version-1 dse=$dse_version-1 dse-hive=$dse_version-1 \
        dse-pig=$dse_version-1 dse-demos=$dse_version-1 dse-libsolr=$dse_version-1 dse-libspark=$dse_version-1 \
        dse-libtomcat=$dse_version-1 dse-libsqoop=$dse_version-1 dse-liblog4j=$dse_version-1 dse-libmahout=$dse_version-1 \
        dse-libhadoop-native=$dse_version-1 dse-libcassandra=$dse_version-1 dse-libhive=$dse_version-1 \
        dse-libpig=$dse_version-1 dse-libhadoop=$dse_version-1"
      if [[ $? -ne 0 ]]; then
        print_error "Failed installing dse, stopping."
        exit 1
      fi
      ;;
    *)
    print_error "$os is not yet supported"
    exit 1
  esac
}

function identify_instance () {
  # identify if a instance belongs to aws, rackspace, openstack, ...
  local sname=$(hostname -d)
  if [[ $sname =~ us-.*\.compute\.internal ]]; then
    echo "aws"
  fi
}

function find_broadcast_address () {
  case "$(identify_instance)" in
    aws)
      public_ip=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
      echo $public_ip
      ;;
    openstack)
      ;;
    physical)
      ;;
    * )
      ;;
  esac
}

function configure_dse () {
  local cassandra_env="/etc/dse/cassandra/cassandra-env.sh"
  local cassandra_config="/etc/dse/cassandra/cassandra.yaml"
  local cassandra_default="/etc/default/dse"
  local eth0_ip_address=$(ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | grep 'Bcast' | awk '{print $1}')

  print_info "Configuring basic dse cassandra..."
  # force cassandra daemon to use jdk installed by this script
  # grep --quiet JAVA_HOME=/opt/java $cassandra_env
  # if [[ $? -ne 0 ]]; then
  #   execute "sed -i '16i\JAVA_HOME=/opt/java' $cassandra_env"
  #   execute "sed -i '17i\JAVA=\$JAVA_HOME/bin/java' $cassandra_env"
  # fi
  grep --quiet JAVA_HOME=/opt/java $cassandra_default
  if [[ $? -ne 0 ]]; then
    execute "echo 'JAVA_HOME=/opt/java' >> $cassandra_default"
  fi
  # Set the cluster name
  execute "sed -i 's/cluster_name:.*/cluster_name: \"$cassandra_cluster_name\"/g' $cassandra_config"
  # confifure cassandra seed nodes
  if [[ -n $cassandra_seeds ]]; then
    execute "sed -i 's/          - seeds:.*/          - seeds: \"$cassandra_seeds\"/g' $cassandra_config"
  fi
  # configure cassandra storage dirs
  local storage_dirs_string="data_file_directories: \n"
  local c=0
  while [[ $c -lt ${#cassandra_data_dirs[@]} ]]; do
    if [[ ! -d ${cassandra_data_dirs[$c]} ]]; then
      mkdir -p ${cassandra_data_dirs[$c]}
      chown cassandra:cassandra ${cassandra_data_dirs[$c]}
    fi
    storage_dirs_string+="  - ${cassandra_data_dirs[$c]}\n"
    let c=c+1
  done
  if [[ ! -d ${cassandra_commit_log_dir} ]]; then
    mkdir -p $cassandra_commit_log_dir
    chown cassandra:cassandra $cassandra_commit_log_dir
  fi
  if [[ ! -d ${cassandra_saved_caches_dir} ]]; then
    mkdir -p ${cassandra_saved_caches_dir}
    chown cassandra:cassandra $cassandra_saved_caches_dir
  fi
  execute "sed -i '/data_file_directories:.*/ {N; s|data_file_directories:.*/var/lib/cassandra/data|${storage_dirs_string}|g}' $cassandra_config"
  execute "sed -i 's|commitlog_directory: /var/lib/cassandra/commitlog|commitlog_directory: ${cassandra_commit_log_dir}|g' $cassandra_config"
  execute "sed -i 's|saved_caches_directory: /var/lib/cassandra/saved_caches|saved_caches_directory: ${cassandra_saved_caches_dir}|g' $cassandra_config"

  execute "sed -i 's/# num_tokens: 256/num_tokens: 256/g' $cassandra_config"
  execute "sed -i 's/listen_address: localhost/listen_address: ${eth0_ip_address}/g' $cassandra_config"
  execute "sed -i 's/rpc_address: localhost/rpc_address: 0.0.0.0/g' $cassandra_config"
  if [[ "$increase_defaults" = "true" ]]; then
    print_info "Bumping up the defaults and timeouts for finetuning cassandra"
    execute "sed -i 's/write_request_timeout_in_ms:.*/write_request_timeout_in_ms: 100000/g' $cassandra_config"
    execute "sed -i 's/read_request_timeout_in_ms:.*/read_request_timeout_in_ms: 100000/g' $cassandra_config"
    execute "sed -i 's/request_timeout_in_ms:.*/request_timeout_in_ms: 100000/g' $cassandra_config"
    execute "sed -i 's/concurrent_writes:.*/concurrent_writes: 64/g' $cassandra_config"
    execute "sed -i 's/# commitlog_total_space_in_mb:.*/commitlog_total_space_in_mb: 4096/g' $cassandra_config"
    execute "sed -i 's/#memtable_flush_writers:.*/memtable_flush_writers: 4/g' $cassandra_config"
  fi
}

function configure_dse_dc () {
  # function params
  local datacenter_name=${1:-DC1}
  local rack_name=${2:-RAC1}

  # static params
  local cassandra_config="/etc/dse/cassandra/cassandra.yaml"
  local dse_dc_config="/etc/dse/cassandra/cassandra-rackdc.properties"

  print_info "Configuring dse datacenter replication..."
  execute "sed -i 's/endpoint_snitch:.*/endpoint_snitch: GossipingPropertyFileSnitch/g' $cassandra_config"
  execute "sed -i 's/dc=.*/dc=${datacenter_name}/g' $dse_dc_config"
  execute "sed -i 's/rack=.*/rack=${rack_name}/g' $dse_dc_config"
}

function configure_dse_broadcast_address () {
  local broadcast_address=$1
  local cassandra_config="/etc/dse/cassandra/cassandra.yaml"

  print_info "Configuring dse broadcast address..."
  if [[ -z $broadcast_address ]]; then
    broadcast_address=$(find_broadcast_address)
  fi
  execute "sed -i 's/# broadcast_address:.*/broadcast_address: ${broadcast_address}/g' $cassandra_config"
}

function configure_dse_heap () {
  local max_heap_size=${1:-4G}
  local heap_newsize=${2:-800M}
  local cassandra_env="/etc/dse/cassandra/cassandra-env.sh"

  print_info "Configuring dse cassandra jvm heap size..."
  execute "sed -i s/#MAX_HEAP_SIZE=.*/MAX_HEAP_SIZE=\"${max_heap_size}\"/g $cassandra_env"
  execute "sed -i s/#HEAP_NEWSIZE=.*/HEAP_NEWSIZE=\"${heap_newsize}\"/g $cassandra_env"
}

function configure_dse_limits () {
  if [[ ! -f /etc/security/limits.d/cassandra.conf ]]; then
    print_info "Updating limits for open files, max processes, memlock's"
    cat > /etc/security/limits.d/cassandra.conf <<LIMITS
cassandra - memlock unlimited
cassandra - nofile 100000
cassandra - nproc 32768
cassandra - as unlimited
LIMITS
    # reload
    execute "sysctl -p"
  fi
}

function configure_spark_memory () {
  local worker_cores=${1:-4}
  local worker_memory=${2:-2048m}
  local spark_env="/etc/dse/spark/spark-env.sh"

  print_info "Configuring spark worker memory"
  execute "sed -s s/# export SPARK_WORKER_MEMORY=.*/export SPARK_WORKER_MEMORY=$worker_memory/g $spark_env"
  execute "sed -s s/# export SPARK_WORKER_CORES=.*/export SPARK_WORKER_CORES=$worker_cores/g $spark_env"
}

function enable_solr () {
  execute "sed -i 's/SOLR_ENABLED=0/SOLR_ENABLED=1/g' /etc/default/dse"
}

function enable_hadoop () {
  execute "sed -i 's/HADOOP_ENABLED=0/HADOOP_ENABLED=1/g' /etc/default/dse"
}

function enable_spark () {
  local spark_env="/etc/dse/spark/spark-env.sh"
  execute "sed -i 's/SPARK_ENABLED=0/SPARK_ENABLED=1/g' /etc/default/dse"
  if [[ ! -d $spark_rdd_dirs ]]; then
    execute "mkdir -p $spark_rdd_dirs"
    execute "chown -R cassandra:cassandra $spark_rdd_dirs"
  fi
  execute "sed -i 's/export SPARK_RDD_DIR=.*/export SPARK_RDD_DIR=\"${spark_rdd_dirs}\"/g' $spark_env"
}

function start_dse () {
  local service="dse"
  local service_count=$(ps -ef | grep -v grep | grep java | grep $service | wc -l)
  if [[ $service_count -gt 0 && "$force_restart" = "true" ]]; then
    print_info "Restarting service $service..."
    execute "service $service restart"
  elif [[ $service_count -gt 0 ]]; then
    print_info "Service $service is already running. Skipping start step."
  else
    print_info "Starting service $service..."
    execute "service $service start"
  fi
}

####
## Main
####

declare cassandra_seeds
declare broadcast_address
declare cassandra_jvm_size
declare cassandra_jvm_newgen_size
declare solr_enabled
declare hadoop_enabled
declare configure_dc_enabled
declare configure_dse_heap_enabled
declare configure_broadcast_enabled
declare dse_datacenter_name
declare dse_rack_name
declare force_restart
declare increase_defaults
declare configure_spark
declare spark_worker_cores
declare spark_worker_memory
declare spark_enabled

function usage () {
  script=$0
  cat <<USAGE
Usage:
-----
Syntax
`basename ${script}` -s -a -d -B [IPv4] -j -J {512M|1G} -N {200M|1G} -h

-B: broadcast address to use
-C: number spark worker cores to use
-D: datacenter name to use (default: DC1)
-J: cassandra jvm size (default: 4G)
-N: cassandra jvm heap new generation size (default: 800M)
-R: rack name to use (default: RAC1)
-S: seeds list to use (example: s1.ex.com,s2.ex.com)
-W: amount of spark worker memory

-a: start dse-hadoop analytics on this machine
-b: attempt to find the broadcast address (use this for virtual instances like aws)
-c: start dse-spark on this machine
-d: configure datacenter replication
-i: increase timeout's and default's for write request, read request, rpc request, concurrent writes, memtable flush writes
-j: configure cassandra jvm heap size
-r: force restart the dse daemon
-s: start dse-solr on this machine

-v: verbose output
-h: show help

Examples:
--------
Install dse cassandra on a single machine:
`basename $script`

Install dse on a cluster with seeds list:
`basename $script` -S "s1.ex.com,s2.ex.com"

Install dse on a cluster with seeds list, configure jvm heap sizes:
`basename $script` -S "s1.ex.com,s2.ex.com" -j -J 8G -N 1G

Install dse on a cluster with Spark enabled and custom worker memory:
`basename $script` -S "s1.ex.com,s2.ex.com" -c -j -J 8G -N 1G -W 6G -C 4
USAGE
  exit 1
}

function check_variables () {
  print_info "Checking user-defined variables for any errors..."

  if [[ -z $datastax_user ]]; then
    print_error "Variable 'datastax_user' is required, set this variable in the script"
    exit 1
  fi
  if [[ -z $datastax_password ]]; then
    print_error "Variable 'datastax_password' is required, set this variable in the script"
    exit 1
  fi
  if [[ -z $dse_version ]]; then
    print_error "Variable 'dse_version' is required, set this variable in the script"
    exit 1
  fi
  if [[ -z $cassandra_data_dirs ]]; then
    print_error "Variable 'cassandra_data_dirs' is required, set this variable in the script to proceed"
    exit 1
  fi
  if [[ -z $cassandra_commit_log_dir ]]; then
    print_error "Variable 'cassandra_commit_log_dir' is required, set this variable in the script to proceed"
    exit 1
  fi
  if [[ -z $cassandra_saved_caches_dir ]]; then
    print_error "Variable 'cassandra_saved_caches_dir' is required, set this variable in the script to proceed"
    exit 1
  fi
  if [[ -z $cassandra_cluster_name ]]; then
    print_error "Variable 'cassandra_cluster_name' is required, set this variable in the script to proceed"
    exit 1
  fi
  if [[ -z $cassandra_seeds ]]; then
    print_warning "Cassandra seeds list is not passed, seeds list is required for deploying cassandra in distributed mode"
  fi
  if [[ "$configure_broadcast_enabled" = "true" ]]; then
    if [[ -z $broadcast_address ]]; then
      print_warning "Broadcast address is not set, set this value if you want cassandra to listen on public ip rather than on private ip"
    fi
  fi
  if [[ "$configure_dc_enabled" = "true" ]]; then
    if [[ -z $dse_datacenter_name ]]; then
      print_warning "Datacenter name not set, default value of 'DC1' will be used"
    fi
    if [[ -z $dse_rack_name ]]; then
      print_warning "Rack name not set, default value of 'RAC1' will be used"
    fi
  fi
  if [[ "$configure_dse_heap_enabled" = "true" ]]; then
    if [[ -z $cassandra_jvm_size ]]; then
      print_warning "jvm size for cassandra is not set, default value of 4G will be used"
    fi
    if [[ -z $cassandra_jvm_newgen_size ]]; then
      print_warning "jvm new generation size is not set, default value of 800M will be used"
    fi
  fi
  # Check if the data_dirs is properly defined
  if [[ ! $(declare -p cassandra_data_dirs) =~ "declare -a" ]]; then
    print_error "Expecting array for variable 'cassandra_data_dirs'."
    exit 1
  fi
}

function main () {
  trap "kill 0" SIGINT SIGTERM EXIT

  # parse command line options
  while getopts B:C:D:J:N:R:S:W:abcdijrsvh opts
  do
    case $opts in
      B)
        broadcast_address=$OPTARG
        ;;
      C)
        configure_spark="true"
        spark_worker_cores=$OPTARG
        ;;
      D)
        dse_datacenter_name=$OPTARG
        ;;
      J)
        cassandra_jvm_size=$OPTARG
        ;;
      N)
        cassandra_jvm_newgen_size=$OPTARG
        ;;
      R)
        dse_rack_name=$OPTARG
        ;;
      S)
        cassandra_seeds=$OPTARG
        ;;
      W)
        configure_spark="true"
        spark_worker_memory=$OPTARG
        ;;
      a)
        hadoop_enabled="true"
        ;;
      b)
        configure_broadcast_enabled="true"
        ;;
      c)
        spark_enabled="true"
        ;;
      d)
        configure_dc_enabled="true"
        ;;
      i)
        increase_defaults="true"
        ;;
      j)
        configure_dse_heap_enabled="true"
        ;;
      r)
        force_restart="true"
        ;;
      s)
        solr_enabled="true"
        ;;
      v)
        debug="true"
        ;;
      h)
        usage
        ;;
      \?)
        usage
        ;;
    esac
  done

  print_banner
  check_variables
  local start_time="$(date +%s)"
  get_system_info
  check_preqs
  stop_iptables
  stop_selinux
  install_oracle_jdk
  configure_jdk
  install_dse
  configure_dse
  if [[ "$solr_enabled" = "true" ]]; then
    enable_solr
  fi
  if [[ "$hadoop_enabled" = "true" ]]; then
    enable_hadoop
  fi
  if [[ "$spark_enabled" = "true" ]]; then
    enable_spark
    if [[ "$configure_spark" = "true" ]]; then
      configure_spark_memory $spark_worker_cores $spark_worker_memory
    fi
  fi
  if [[ "$configure_dc_enabled" = "true" ]]; then
    configure_dse_dc $dse_datacenter_name $dse_rack_name
  fi
  if [[ "$configure_dse_heap_enabled" = "true" ]]; then
    configure_dse_heap $cassandra_jvm_size $cassandra_jvm_newgen_size
  fi
  if [[ "$configure_broadcast_enabled" = "true" ]]; then
    configure_dse_broadcast_address $broadcast_address
  fi
  start_dse
  local end_time="$(date +%s)"
  print_info "Execution complete. Time took: $((end_time - start_time)) second(s)"
}

main $@