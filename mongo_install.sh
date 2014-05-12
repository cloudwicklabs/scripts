#!/bin/bash
#
# Author:: Ashrith Mekala (<ashrith@cloudwick.com>)
# Description:: Script to install MongoDB with MMS Agent in sharded &
#               replicated mode
# Version:: 0.1
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
# where mongo stores data
mongo_data_dir="/mongo/data"

####
## Configuration Variables (change these, only if you know what you are doing)
####
# mongo version to install
mongo_version="2.4.9"

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

  for command in curl vim ruby; do
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

function add_10gen_repo () {
  case "$os" in
    centos|redhat)
      if [[ ! -f /etc/yum.repos.d/mongodb.repo ]]; then
        print_info "Adding 10gen to yum repositories list..."
        if [[ $os_arch == "x86_64" ]]; then
          cat > /etc/yum.repos.d/mongodb.repo <<-EOF
[mongodb]
name=MongoDB Repository
baseurl=http://downloads-distro.mongodb.org/repo/redhat/os/x86_64/
gpgcheck=0
enabled=1
EOF
        else
          cat > /etc/yum.repos.d/mongodb.repo <<EOF
[mongodb]
name=MongoDB Repository
baseurl=http://downloads-distro.mongodb.org/repo/redhat/os/i686/
gpgcheck=0
enabled=1
EOF
        fi
      fi
      ;;
    ubuntu)
      if [[ ! -f /etc/apt/sources.list.d/datastax.sources.list ]]; then
        print_info "Adding 10gen repo to apt sources list"
        print_debug "Importing 10gen public GPG key"
        execute "apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10"
        execute "echo \"deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen\" | tee /etc/apt/sources.list.d/mongodb.list"
        print_info "Refreshing apt packages list..."
        execute "apt-get update"
      fi
      ;;
    *)
      print_error "$os is not yet supported, please contact support@cloudwicklabs.com."
      exit 1
      ;;
  esac
}

function add_epel_repo () {
  execute "ls -la /etc/yum.repos.d/*epel*"
  if [[ $? -ne 0 ]]; then
    print_info "Adding the EPEL repository to yum configuration..."
    if [[ $os_version -eq 5 ]]; then
      execute "curl -o epel.rpm -L http://download.fedoraproject.org/pub/epel/5/$os_arch/epel-release-5-4.noarch.rpm"
      execute "rpm -i epel.rpm"
      execute "rm -f epel.rpm"
    elif [[ $os_version -eq 6 ]]; then
      execute "curl -o epel.rpm -L http://download.fedoraproject.org/pub/epel/6/$os_arch/epel-release-6-8.noarch.rpm"
      execute "rpm -i epel.rpm"
      execute "rm -f epel.rpm"
    fi
  fi
}

function stop_iptables () {
  case "$os" in
    centos|redhat)
      print_info "Stopping ip tables..."
      execute "service iptables stop"
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

function check_if_mongo_is_installed () {
  print_info "Checking to see if mongodb is installed..."
  case "$os" in
    centos|redhat)
      execute "rpm -q mongo-10gen-${mongo_version}"
      return $?
      ;;
    ubuntu)
      execute "dpkg --list | grep mongodb-10gen | grep ${mongo_version}"
      return $?
      ;;
    *)
      print_error "$os is not supported yet."
      exit 1
      ;;
  esac
}

function install_mongo () {
  check_if_mongo_is_installed
  if [[ $? -eq 0 ]]; then
    print_info "Package mongodb-10gen version: \"$mongo_version\" is already installed. Skipping installation step."
    return
  fi
  add_10gen_repo
  print_info "Installing mongodb-10gen version:${mongo_version}..."
  case "$os" in
    centos|redhat)
      # where mongo-10gen-server contains mongod and mongos daemons
      execute "$package_manager install -y mongo-10gen-${mongo_version} mongo-10gen-server-${mongo_version}"
      if [[ $? -ne 0 ]]; then
        print_error "Failed installing mongo-10gen, stopping."
        exit 1
      fi
      ;;
    ubuntu)
      execute "$package_manager install -y mongodb-10gen=${mongo_version}"
      if [[ $? -ne 0 ]]; then
        print_error "Failed installing mongo-10gen, stopping."
        exit 1
      fi
      execute "service mongodb stop" # ubuntu starts service on installation
      ;;
    *)
    print_error "$os is not yet supported"
    exit 1
  esac
}

function configure_mongo () {
  if [[ $os =~ centos || $os =~ redhat ]]; then
    local mongo_config="/etc/mongod.conf"
  elif [[ $os =~ ubuntu ]]; then
    local mongo_config="/etc/mongodb.conf"
  fi
  local eth0_ip_address=$(ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | grep 'Bcast' | awk '{print $1}')

  if [[ ! -d ${mongo_data_dir} ]]; then
    mkdir -p ${mongo_data_dir}
    chown mongodb:mongodb ${mongo_data_dir}
  fi

  if [[ $mongo_router = "true" ]]; then
    print_info "Configuring mongo router..."
    cat > ${mongo_config} <<EOF
#config servers
configdb=host1:27019,host2:27019,host3:27019

#where to log
logpath=/var/log/mongo/mongos.log

#log overwritten or appended to
logappend=true

#fork and run in background
fork=true

#override port
port=27017
EOF
  elif [[ $mongo_shard_server ]]; then
    print_info "Configuring shard server with replica set ${mongo_replica_set_name}..."
    cat > ${mongo_config} <<EOF
#mongod config file

#replica set
replSet=${mongo_replica_set_name}

#start mongod in shardsvr mode
shardsvr=true

#where to log
logpath=/var/log/mongo/mongod.log

#log overwritten or appended to
logappend=true

#fork and run in background
fork=true

#override port
port=27018

#path to data files
dbpath=${mongo_data_dir}
EOF
  elif [[ $mongo_config_server ]]; then
    print_info "Configuring mongo config server..."
    cat > ${mongo_config} <<EOF
#configsvr config file

#start mongod in configsvr mode
configsvr=true

#where to log
logpath=/var/log/mongo/mongod.log

#log overwritten or appended to
logappend=true

#fork and run in background
fork=true

#override port
port=27019

#path to data files
dbpath=${mongo_data_dir}
EOF
  fi

  grep --quiet 'dbpath' ${mongo_config}
  if [[ $? -ne 0 ]]; then
    printf "\ndbpath=${mongo_data_dir}\n" >> $mongo_config
  fi

  if [[ $mongo_bind_ip = "true" ]]; then
    printf "\nbind_ip=${eth0_ip_address}\n" >> $mongo_config
  fi
}

function start_mongo () {
  if [[ $os =~ centos || $os =~ redhat ]]; then
    local service="mongod"
  else
    local service="mongodb"
  fi
  local service_count=$(ps -ef | grep -v grep | grep $service | wc -l)
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

function initialize_replica_set () {
  local init_json=""
  local validate_members=$(ruby -e "ARGV[0].split(',').each { |a| puts 'invalid' unless a =~ /.*?:/ }" $mongo_replica_set_members)
    if [[ $validate_members =~ invalid ]]; then
      print_error "Invalid replica members format, possible format: HOST|BIND_IP:PORT ex: r1.cw.com:27018,r2.cw.com:27018,r3.cw.com:27018"
      exit 1
    fi
  if [[ ! -z $mongo_arbiter_server ]]; then
    local validate_arbiter=$(ruby -e "ARGV[0].split(',').each { |a| puts 'invalid' unless a =~ /.*?:/ }" $mongo_arbiter_server)
    if [[ $validate_arbiter =~ invalid ]]; then
      print_error "Invalid arbiter server format, possible format: HOST|IP:PORT ex: arbiter.cw.com:27018"
      exit 1
    fi
  fi
  init_json=$(/usr/bin/ruby <<EOR
arbiter_nodes = "${mongo_arbiter_server}".split(',')
members = "${mongo_replica_set_members}".split(',').each_with_index.map do |host, id|
  is_arbiter = (arbiter_nodes.include?(host)) ? true : false
  "{ _id: #{id}, host: \"#{host}\", arbiterOnly : #{is_arbiter} }"
end.join(',')
puts members
EOR
)

  mongo <<EOF
  rs.initiate(${init_json})
EOF
}

function start_mongos () {
  local service="mongos"
  local service_count=$(ps -ef | grep -v grep | grep $service | wc -l)
  if [[ $service_count -gt 0 ]]; then
    print_info "Service $service is already running. Skipping start of $service."
  else
    print_info "Starting service $service..."
    execute "mongos --config ${mongo_config}"
  fi
}

function mongo_mms_dependencies () {
  print_info "Installing dependencies for mms..."
  case "$os" in
    centos|redhat)
      # where mongo-10gen-server contains mongod and mongos daemons
      execute "$package_manager install -y python python-setuptools gcc python-devel"
      if [[ $? -ne 0 ]]; then
        print_error "Failed installing dependencies for mms agent, this might cause mms intallation to fail"
      fi
      ;;
    ubuntu)
      execute "$package_manager install -y python python-setuptools build-essential python-dev"
      if [[ $? -ne 0 ]]; then
        print_error "Failed installing dependencies for mms agent, this might cause mms intallation to fail"
      fi
      ;;
    *)
    print_error "$os is not yet supported"
    exit 1
  esac
  print_info "Installing pymongo as a mms dependency..."
  execute "easy_install pymongo"
}

function install_mongo_mms () {
  if [[ ! -d /opt/mms-agent ]]; then
    mongo_mms_dependencies
    print_info "Downloading and extracting mms package"
    execute "(cd /opt && curl -O https://mms.mongodb.com/settings/mms-monitoring-agent.tar.gz)"
    if [[ $? -eq 0 ]]; then
      execute "(cd /opt && tar xzf mms-monitoring-agent.tar.gz)"
      execute "(cd /opt && rm -f mms-monitoring-agent.tar.gz)"
    else
      print_error "Failed installing mongo mms agent"
    fi
  fi
}

function configure_mongo_mms () {
  local mms_config="/opt/mms-agent/settings.py"
  execute "sed -i 's/mms_key = \"@API_KEY@\"/mms_key = \"${mongo_mms_api_key}\"/g' ${mms_config}"
  execute "sed -i 's/mms_server = \"@MMS_SERVER@\"/mms_server = \"https:\/\/mms.mongodb.com\"/g' ${mms_config}"
  execute "sed -i 's/sslRequireValidServerCertificates = @DEFAULT_REQUIRE_VALID_SERVER_CERTIFICATES@/sslRequireValidServerCertificates = False/g' ${mms_config}"
}

function start_mongo_mms () {
  local service="agent.py"
  local service_count=$(ps -ef | grep -v grep | grep python | grep $service | wc -l)
  if [[ $service_count -gt 0 ]]; then
    print_info "Service mms-agent is already running. Skipping start of $service."
  else
    print_info "Starting service mms-agent..."
    if [[ ! -d /var/log/mms ]]; then
      mkdir -p /var/log/mms
    fi
    execute "nohup python /opt/mms-agent/agent.py >> /var/log/mms/agent.log  2>&1 &"
  fi
}

# Hardware monitoring using munin

function check_if_munin_is_installed () {
  print_info "Checking to see if mongodb is installed..."
  case "$os" in
    centos|redhat)
      execute "rpm -q munin-node"
      return $?
      ;;
    ubuntu)
      execute "dpkg --list | grep munin-node"
      return $?
      ;;
    *)
      print_error "$os is not supported yet."
      exit 1
      ;;
  esac
}

function install_munin () {
  if [[ $os =~ centos || $os =~ redhat ]]; then
    add_epel_repo
  fi
  check_if_munin_is_installed
  if [[ $? -ne 0 ]]; then
    print_info "Installing munin-node package..."
    execute "${package_manager} install -y munin-node"
  else
    print_info "Package munin-node is already installed. Skipping installation step."
  fi
}

function configure_munin () {
  local munin_config="/etc/munin/plugin-conf.d/munin-node"
  if [[ $os =~ centos || $os =~ redhat ]]; then
    if [[ ! -f /etc/munin/plugins/iostat ]]; then
      ln -s /usr/share/munin/plugins/iostat /etc/munin/plugins/iostat
      ln -s /usr/share/munin/plugins/iostat_ios /etc/munin/plugins/iostat_ios
    fi
  fi

  grep --quiet '[iostat]' $munin_config
  if [[ $? -ne 0 ]]; then
    printf "\n[iostat]\tenv.SHOW_NUMBERED 1" >> $munin_config
    execute "service munin-node restart"
  fi
}

####
## Main
####

declare mongo_router
declare mongo_shard_server
declare mongo_config_server
declare mongo_replica_server_primary
declare mongo_replica_server_slave
declare mongo_replica_set_name
declare mongo_initialize_replica_set
declare mongo_arbiter_server
declare mongo_bind_ip
declare mongo_mms_install
declare mongo_mms_api_key
declare force_restart
declare debug

function usage () {
  script=$0
  cat <<USAGE
Syntax
`basename ${script}` OPTS

where OPTS are:
-l: start mongo router instance (load balancer)
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
`basename $script`

Install mongo on a cluster mode with 2 replica sets:
1. Start mongo router instance
  `basename $script` -l -C host1:27019,host2:27019,host3:27019
2. Start mongo replica server master (s1r1.cw.com)
  `basename $script` -s -R replA -S master
3. Start mongo replica server slave (s1r2.cw.com)
  `basename $script` -s -R replA -S slave
4. Start mongo arbiter server (s1a1.cw.com)
  `basename $script` -s -R replA -a
5. Start mongo replica server master (s2r1.cw.com)
  `basename $script` -s -R replB -S master
6. Start mongo replica server slave (s2r2.cw.com)
  `basename $script` -s -R replB -S slave
7. Start mongo arbiter server (s2a1.cw.com)
  `basename $script` -s -a -R replB
8. Start config server1
  `basename $script` -c
9. Start config server2
  `basename $script` -c
10. Start config server3
  `basename $script` -c
11. Initialize replica set 1, run this from replica (replA) primary master
  `basename $script` -I "s1r1.cw.com:27018,s1r2.cw.com:27018,s1a1.cw.com:27018" -A "s1a1.cw.com:27018"
12. Initialize replica set 2, run this from replica (replB) primary master
  `basename $script` -I "s2r1.cw.com:27018,s2r2.cw.com:27018,s2a1.cw.com:27018" -A "s2a1.cw.com:27018"

USAGE
  exit 1
}

function check_variables () {
  print_info "Checking user-defined variables for any errors..."

  if [[ -z $mongo_version ]]; then
    print_error "Variable 'mongo_version' is required, set this variable in the script"
    exit 1
  fi
  if [[ -z $mongo_data_dir ]]; then
    print_error "Variable 'mongo_data_dir' is required, set this variable in the script to proceed"
    exit 1
  fi
  if [[ $mongo_router = "true" ]]; then
    if [[ -z $mongo_configdb ]]; then
      print_error "Configuring mongo router requries list of config serves set using option -C"
      exit 1
    fi
  fi
  if [[ ! -z $mongo_initialize_replica_set ]]; then
    if [[ -z $mongo_arbiter_server ]]; then
      print_warning "Initializing a replica set, no arbiter will be configured"
    fi
  fi
  if [[ ! -z $mongo_mms_install ]]; then
    if [[ -z $mongo_mms_api_key ]]; then
      print_error "Mongo mms api key is required for mms installation, pass using -K"
      exit 1
    fi
  fi
}

function main () {
  trap "kill 0" SIGINT SIGTERM EXIT

  # parse command line options
  while getopts S:C:M:R:I:A:K:slcamivh opts
  do
    case $opts in
      l)
        mongo_router="true"
        ;;
      s)
        mongo_shard_server="true"
        ;;
      c)
        mongo_config_server="true"
        ;;
      a)
        mongo_arbiter_server="true"
        ;;
      b)
        mongo_bind_ip="true"
        ;;
      m)
        mongo_mms_install="true"
        ;;
      R)
        mongo_replica_set_name=$OPTARG
        ;;
      S)
        mongo_replica_set_config=$OPTARG
        ;;
      C)
        mongo_configdb=$OPTARG
        ;;
      M)
        mongo_replica_set_members=$OPTARG
        ;;
      I)
        mongo_initialize_replica_set=$OPTARG
        ;;
      A)
        mongo_arbiter_server=$OPTARG
        ;;
      K)
        mongo_mms_api_key=$OPTARG
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
  install_mongo
  configure_mongo
  if [[ $mongo_router = "true" ]]; then
    start_mongos
  else
    start_mongo
  fi
  if [[ $mongo_mms_install = "true" ]]; then
    install_mongo_mms
    configure_mongo_mms
    start_mongo_mms
    install_munin
    configure_munin
  fi
  if [[ ! -z $mongo_initialize_replica_set ]]; then
    mongo_initialize_replica_set
  fi
  local end_time="$(date +%s)"
  print_info "Execution complete. Time took: $((end_time - start_time)) second(s)"
}

main $@
