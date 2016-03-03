#!/bin/bash
#
# Author:: Ashrith Mekala (<ashrith@cloudwick.com>)
# Description:: Script to install puppet server/client v4.x
#               * puppetdb for stored configs
#               * postgresql (dependency for puppetdb)
#               * auto signing for puppet clients belonging to same domain
# Supported OS:: CentOS 6/7, RedHat 6/7, Ubuntu precise/lucid/trusty
# Version: 0.6
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

### !!! DONT CHANGE BEYOND THIS POINT. DOING SO MAY BREAK THE SCRIPT !!!

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
stdout_log="/tmp/puppet-install.stdout"
stderr_log="/tmp/puppet-install.stderr"

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
  printf "%s %b[ERROR]%b $*\n" "$(date +%s)" "${clr_red}" "${clr_end}"
}

function print_warning () {
  printf "%s %b[WARN]%b $*\n" "$(date +%s)" "${clr_yellow}" "${clr_end}"
}

function print_info () {
  printf "%s %b[INFO]%b $*\n" "$(date +%s)" "${clr_green}" "${clr_end}"
}

function print_debug () {
  if [[ ${debug} = "true" ]]; then
    printf "%s %b[DEBUG]%b $*\n" "$(date +%s)" "${clr_cyan}" "${clr_end}"
  fi
}

function execute () {
  local full_redirect="1>>$stdout_log 2>>$stderr_log"
  /bin/bash -c "$* $full_redirect"
  ret=$?
  if [ ${ret} -ne 0 ]; then
    print_debug "Executed command \'$*\', returned non-zero code: ${clr_yellow}${ret}${clr_end}"
  else
    print_debug "Executed command \'$*\', returned successfully."
  fi
  return ${ret}
}

function check_for_root () {
  if [ "$(id -u)" != "0" ]; then
   print_error "Please run with super user privileges."
   exit 1
  fi
}

function get_system_info () {
  print_debug "Collecting system configuration..."

  os=$(uname -s)
  if [[ "$os" = "SunOS" ]] ; then
    os="Solaris"
    os_arch=$(uname -p)
  elif [[ "$os" = "Linux" ]] ; then
    if [[ -f /etc/redhat-release ]]; then
      os_str=$( cat `ls /etc/*release | grep "redhat\|SuSE"` | head -1 | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } print $i; } }' | tr '[:upper:]' '[:lower:]' )
      os_version=$( cat `ls /etc/*release | grep "redhat\|SuSE"` | head -1 | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } } }' | tr '[:upper:]' '[:lower:]' )
      if [[ ${os_str} =~ centos ]]; then
        os="centos"
      elif [[ ${os_str} =~ red ]]; then
        os="redhat"
      else
        print_error "OS: $os_str is not yet supported, contact support@cloudwicklabs.com"
        exit 1
      fi
    elif [[ -f /etc/lsb-release ]] ; then
      os_str=$( lsb_release -sd | tr '[:upper:]' '[:lower:]' | tr '"' ' ' | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } print $i; } }' )
      os_version=$( lsb_release -sd | tr '[:upper:]' '[:lower:]' | tr '"' ' ' | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } } }')
      if [[ ${os_str} =~ ubuntu ]]; then
        os="ubuntu"
        os_codename=$( grep DISTRIB_CODENAME /etc/lsb-release | cut -d'=' -f2 )
        if [[ "${os_codename}" != "precise" && "${os_codename}" != "lucid" && "${os_codename}" != "trusty" ]]; then
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
    os="${os// */}"
    os_arch=$(uname -m)
    if [[ "xi686" == "x${os_arch}" || "xi386" == "x${os_arch}" ]]; then
      os_arch="i386"
    fi
    if [[ "xx86_64" == "x${os_arch}" || "xamd64" == "x${os_arch}" ]]; then
      os_arch="x86_64"
    fi
  elif [[ "$os" = "Darwin" ]]; then
    type -p sw_vers &>/dev/null
    if [[ $? -eq 0 ]]; then
      os="macosx"
      os_version=$(sw_vers | grep 'ProductVersion' | cut -f 2)
    else
      os="macosx"
    fi
  fi

  if [[ ${os} =~ centos || ${os} =~ redhat ]]; then
    if [[ ${os_version} -le 5 ]]; then
      print_error "Unsupported os version. Please contact support@cloudwicklabs.com."
      exit 1
    fi
    package_manager="yum"
  elif [[ ${os} =~ ubuntu ]]; then
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

  for command in curl vim; do
    type -P ${command} &> /dev/null || {
      print_warning "Command $command not found"
      print_info "Attempting to install $command..."
      execute "${package_manager} -y install $command" # brew does not have -y
      if [[ $? -ne 0 ]]; then
        print_warning "Could not install $command. This may cause issues."
      fi
    }
  done
}

function add_epel_repo () {
  execute "ls -la /etc/yum.repos.d/*epel*"
  if [[ $? -ne 0 ]]; then
    print_info "Adding the EPEL repository to yum configuration..."
    if [[ ${os_version} -eq 6 ]]; then
      execute "rpm -i http://download.fedoraproject.org/pub/epel/6/$os_arch/epel-release-6-8.noarch.rpm"
    elif [[ ${os_version} -eq 7 ]]; then
      execute "rpm -i http://dl.fedoraproject.org/pub/epel/7/$os_arch/e/epel-release-7-5.noarch.rpm"
    fi
  fi
}

function add_puppetlabs_repo () {
  case "$os" in
    centos|redhat)
      add_epel_repo
      if [[ ! -f /etc/yum.repos.d/puppetlabs.repo ]]; then
        print_info "Adding puppetlabs repo to yum repositories list..."
        if [[ ${os_version} -eq 6 ]]; then
          execute "rpm -i https://yum.puppetlabs.com/puppetlabs-release-pc1-el-6.noarch.rpm"
        elif [[ ${os_version} -eq 7 ]]; then
          execute "rpm -i https://yum.puppetlabs.com/puppetlabs-release-pc1-el-7.noarch.rpm"
        fi
        sed -i 's/gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/puppetlabs*.repo
      fi
      ;;
    ubuntu)
      if [[ ! -f /etc/apt/sources.list.d/puppetlabs.list ]]; then
        print_info "Adding puppetlabs repo to apt sources list"
        execute "curl -sO https://apt.puppetlabs.com/puppetlabs-release-pc1-${os_codename}.deb"
        execute "dpkg -i puppetlabs-release-${os_codename}.deb"
        execute "rm -f puppetlabs-release-${os_codename}.deb"
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

function add_postgres_repo () {
  case "$os" in
    centos|redhat)
      if [[ ! -f /etc/yum.repos.d/pgdg-95-redhat.repo ]]; then
        print_info "Adding postgres repo to yum repositories list..."
        if [[ ${os_version} -eq 6 ]]; then
          execute "rpm -Uvh http://yum.postgresql.org/9.5/redhat/rhel-6-x86_64/pgdg-redhat95-9.5-2.noarch.rpm"
        elif [[ ${os_version} -eq 7 ]]; then
          execute "rpm -Uvh http://yum.postgresql.org/9.5/redhat/rhel-7-x86_64/pgdg-redhat95-9.5-2.noarch.rpm"
        fi
        sed -i 's/gpgcheck=1/gpgcheck=0/g' /etc/yum.repos.d/pgdg-95-redhat.repo
      fi
      ;;
    ubuntu)
      if [[ ! -f /etc/apt/sources.list.d/pgdg.list ]]; then
        print_info "Adding postgres repo to apt sources list"
        execute "echo deb http://apt.postgresql.org/pub/repos/apt/ ${os_codename}-pgdg main >> /etc/apt/sources.list.d/pgdg.list"
        execute "wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O - | sudo apt-key add -"
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

function stop_iptables () {
  case "$os" in
    centos|redhat)
      print_info "Stopping ip tables..."
      if [[ ${os_version} -eq 6 ]]; then
        execute "service iptables stop"
        execute "chkconfig iptables off"
      elif [[ ${os_version} -eq 7 ]]; then
        execute "service firewalld stop"
        execute "systemctl disable firewalld"
      fi
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

function check_if_postgres_is_installed () {
  print_info "Checking to see if postgres is installed..."
  case "$os" in
    centos|redhat)
      execute "rpm -q postgresql95-server"
      return $?
      ;;
    ubuntu)
      execute "dpkg --list | grep postgresql-9.5"
      return $?
      ;;
    *)
      print_error "$os is not supported yet."
      exit 1
      ;;
  esac
}

function install_postgres () {
  add_postgres_repo
  check_if_postgres_is_installed
  if [[ $? -eq 0 ]]; then
    print_info "Package postgres is already installed. Skipping installation step."
    return
  fi
  print_info "Installing postgres..."
  case "$os" in
    centos|redhat)
      execute "$package_manager install -y postgresql95 postgresql95-server postgresql95-contrib"
      if [[ $? -ne 0 ]]; then
        print_error "Failed installing postgresql-server, stopping."
        exit 1
      fi
      print_info "Initializing postgresql db..."
      if [[ ${os_version} -eq 6 ]]; then
        execute "service postgresql-9.5 initdb"
      else
        execute "/usr/pgsql-9.5/bin/postgresql95-setup initdb"
      fi
      ;;
    ubuntu)
      execute "$package_manager install -y postgresql-9.5 postgresql-contrib-9.5"
      if [[ $? -ne 0 ]]; then
        print_error "Failed installing postgresql, stopping."
        exit 1
      fi
      ;;
    *)
    print_error "$os is not yet supported"
    exit 1
  esac
}

function configure_postgres () {
  local file_change="false"
  print_info "Configuring postgres..."
  case "$os" in
    centos|redhat)
      local psql_config="/var/lib/pgsql/9.5/data/pg_hba.conf"
      local psql_data_conf="/var/lib/pgsql/9.5/data/postgresql.conf"
      sed -e "s|local *all *postgres .*|local    all         postgres                   trust|g" \
          -e "s|local *all *all .*|local    all         all                   trust|g" \
          -e "s|host *all *all *127.0.0.1/32 .*|host    all         all        127.0.0.1/32           trust|g" \
          -e "s|host *all *all *::1/128 .*|host    all         all        ::1/128           trust|g" \
          -i ${psql_config}
      execute "grep puppetdb $psql_config"
      if [[ $? -ne 0 ]]; then
        file_change="true"
        echo 'host puppetdb puppetdb 0.0.0.0/0 trust' >> ${psql_config}
      fi
      execute "grep \"listen_addresses = '0.0.0.0'\" $psql_data_conf"
      if [[ $? -ne 0 ]]; then
        file_change="true"
        echo "listen_addresses = '0.0.0.0'" >> ${psql_data_conf}
      fi
      if [[ "$file_change" = "true" ]]; then
        print_info "Restarting postgresql to reload config"
        if [[ $os_version -eq 6 ]]; then
          execute "service postgresql-9.5 restart"
        else
          execute "systemctl restart postgresql-9.5"
        fi
      fi
      ;;
    ubuntu)
      local psql_config="/etc/postgresql/9.5/main/pg_hba.conf"
      local psql_data_conf="/etc/postgresql/9.5/main/postgresql.conf"
      sed -e "s|local *all *postgres .*|local    all         postgres                   trust|g" \
          -e "s|local *all *all .*|local    all         all                   trust|g" \
          -e "s|host *all *all *127.0.0.1/32 .*|host    all         all        127.0.0.1/32           trust|g" \
          -e "s|host *all *all *::1/128 .*|host    all         all        ::1/128           trust|g" \
          -i "$psql_config"
      execute "grep puppetdb $psql_config"
      if [[ $? -ne 0 ]]; then
        file_change="true"
        echo 'host  puppetdb  puppetdb  0.0.0.0/0   trust' >> "$psql_config"
      fi
      execute "grep \"listen_addresses = '0.0.0.0'\" $psql_data_conf"
      if [[ $? -ne 0 ]]; then
        file_change="true"
        echo "listen_addresses = '0.0.0.0'" >> "$psql_data_conf"
      fi
      if [[ "$file_change" = "true" ]]; then
        print_info "Restarting postgresql to reload config"
        execute "service postgresql restart"
      fi
      ;;
    *)
    print_error "$os is not yet supported"
    exit 1
  esac
}

function start_postgres () {
  local service
  local service_count
  service="postgresql-9.5"
  service_count=$(pgrep -f postmaster | wc -l)
  case "$os" in
    centos|redhat)
      if [[ ${os_version} -eq 6 ]]; then
        if [[ ${service_count} -gt 0 && "$force_restart" = "true" ]]; then
          print_info "Restarting service $service..."
          execute "service $service restart"
        elif [[ ${service_count} -gt 0 ]]; then
          print_info "Service $service is already running. Skipping start step."
        else
          print_info "Starting service $service..."
          execute "service $service start"
          execute "chkconfig $service on"
        fi
      elif [[ ${os_version} -eq 7 ]]; then
        if [[ ${service_count} -gt 0 && "$force_restart" = "true" ]]; then
          print_info "Restarting service $service..."
          execute "systemctl restart $service"
        elif [[ ${service_count} -gt 0 ]]; then
          print_info "Service $service is already running. Skipping start step."
        else
          print_info "Starting service $service..."
          execute "systemctl start $service"
          execute "systemctl enable $service"
        fi
      fi
      ;;
    ubuntu)
      if [[ ${service_count} -gt 0 && "$force_restart" = "true" ]]; then
        print_info "Restarting service $service..."
        execute "service postgresql restart"
      elif [[ ${service_count} -gt 0 ]]; then
        print_info "Service $service is already running. Skipping start step."
      else
        print_info "Starting service $service..."
        execute "service $service start"
      fi
      ;;
    *)
      print_error "$os is not supported"
      exit 1
  esac
}

function configure_postgres_users () {
  sudo -u postgres psql template1 <<END 1>>${stdout_log} 2>>${stderr_log}
create user puppetdb with password '${postgresql_password}';
create database puppetdb with owner puppetdb;
END
}

function check_if_puppet_server_is_installed () {
  print_info "Checking to see if puppet is installed..."
  case "$os" in
    centos|redhat)
      execute "rpm -q puppetserver"
      return $?
      ;;
    ubuntu)
      execute "dpkg --list | grep puppetserver"
      return $?
      ;;
    *)
      print_error "$os is not supported yet."
      exit 1
      ;;
  esac
}

function install_puppet_server () {
  check_if_puppet_server_is_installed
  if [[ $? -eq 0 ]]; then
    print_info "Package puppet is already installed. Skipping installation step."
    return
  fi
  add_puppetlabs_repo
  print_info "Installing puppet server package..."
  case "$os" in
    centos|redhat)
      execute "$package_manager install -y puppetserver"
      if [[ $? -ne 0 ]]; then
        print_error "Failed installing puppet-server, stopping."
        exit 1
      fi
      ;;
    ubuntu)
      execute "$package_manager install -y puppetserver"
      if [[ $? -ne 0 ]]; then
        print_error "Failed installing puppetmaster, stopping."
        exit 1
      fi
      ;;
    *)
    print_error "$os is not yet supported"
    exit 1
  esac
}

function configure_puppet_server () {
  local eth0_ip_address=$(ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | grep 'Bcast' | awk '{print $1}')
  local puppet_server_fqdn=$(hostname --fqdn)
  local puppet_server_config_file="/etc/puppetlabs/puppetserver/conf.d/puppetserver.conf"
  local puppet_config_file="/etc/puppetlabs/puppet/puppet.conf"

  # TODO configure memory settings based on available system memory
  case "$os" in
    centos|redhat)
      sed -e "s|JAVA_ARGS.*|JAVA_ARGS=\"-Xms2g -Xmx2g -XX:MaxPermSize=256m\"|" -i /etc/sysconfig/puppetserver
      ;;
    ubuntu)
      sed -e "s|JAVA_ARGS.*|JAVA_ARGS=\"-Xms2g -Xmx2g -XX:MaxPermSize=256m\"|" -i /etc/default/puppetserver
      ;;
  esac

  cat > ${puppet_config_file} <<END
[main]
server = ${puppet_server_fqdn}
certname = ${puppet_server_fqdn}
environment = production

[master]
vardir = /opt/puppetlabs/server/data/puppetserver
logdir = /var/log/puppetlabs/puppetserver
rundir = /var/run/puppetlabs/puppetserver
pidfile = /var/run/puppetlabs/puppetserver/puppetserver.pid
codedir = /etc/puppetlabs/code

END
}

function configure_autosign_certificates () {
  local puppet_server_fqdn=$(hostname --fqdn)
  local domain_name=$(echo "$puppet_server_fqdn" | cut -d "." -f 2-)
  echo "*.${domain_name}" > /etc/puppetlabs/puppet/autosign.conf
}

function start_puppet_server () {
  print_info "Starting puppet master service..."
  execute "/opt/puppetlabs/bin/puppet resource service puppetserver ensure=running"
}

function stop_puppet_server () {
  print_info "Stopping puppet master service..."
  execute "/opt/puppetlabs/bin/puppet resource service puppetmaster ensure=stopped"
}

function check_if_puppet_client_is_installed () {
  print_info "Checking to see if puppet agent is installed..."
  case "$os" in
    centos|redhat)
      execute "rpm -q puppet-agent"
      return $?
      ;;
    ubuntu)
      execute "dpkg --list | grep puppet-agent"
      return $?
      ;;
    *)
      print_error "$os is not supported yet."
      exit 1
      ;;
  esac
}

function install_puppet_client () {
  check_if_puppet_client_is_installed
  if [[ $? -eq 0 ]]; then
    print_info "Package puppet is already installed. Skipping installation step."
    return
  fi
  add_puppetlabs_repo
  print_info "Installing puppet agent package..."
  execute "$package_manager install -y puppet-agent"
  if [[ $? -ne 0 ]]; then
    print_error "Failed installing puppet, stopping."
    exit 1
  fi
}

function configure_puppet_client () {
  print_info "Configuring puppet agent..."
  cat > /etc/puppetlabs/puppet/puppet.conf <<END
[main]
server = ${puppet_server_hostname}
environment = production
runinterval = 1h
END
}

function start_puppet_client () {
  print_info "Starting puppet agent"
  execute "/opt/puppetlabs/bin/puppet resource service puppet ensure=running enable=true"
}

function setup_puppet_client_cron_job () {
  print_info "Setting up cron job to start puppet agent"
  execute "/opt/puppetlabs/bin/puppet resource cron puppet-agent ensure=present user=root minute=30 command='/opt/puppetlabs/bin/puppet agent --onetime --no-daemonize --splay --splaylimit 60'"
}

function test_puppet_run () {
  print_info "Executing test puppet run"
  execute "/opt/puppetlabs/bin/puppet agent --test"
  if [[ $? -eq 0 ]]; then
    print_info "Successfully executed puppet run"
  else
    print_warning "Failed executing test puppet run"
  fi
}

function check_if_puppetdb_is_installed () {
  print_info "Checking to see if puppetdb is installed..."
  case "$os" in
    centos|redhat)
      execute "rpm -q puppetdb"
      return $?
      ;;
    ubuntu)
      execute "dpkg --list | grep puppetdb"
      return $?
      ;;
    *)
      print_error "$os is not supported yet."
      exit 1
      ;;
  esac
}

function install_puppetdb () {
  check_if_puppetdb_is_installed
  if [[ $? -eq 0 ]]; then
    print_info "Package puppetdb is already installed. Skipping installation step."
    return
  fi
  print_info "Installing puppetdb package"
  execute "$package_manager -y install puppetdb puppetdb-terminus"
  if [[ $? -ne 0 ]]; then
    print_error "Failed installing puppetdb, stopping."
    exit 1
  fi
}

function configure_puppetdb () {
  local puppetdb_default
  local puppet_server_fqdn=$(hostname --fqdn)
  case "$os" in
    centos|redhat)
      puppetdb_default="/etc/sysconfig/puppetdb"
      ;;
    ubuntu)
      puppetdb_default="/etc/default/puppetdb"
      ;;
    *)
      print_error "$os is not supported yet."
      exit 1
      ;;
  esac
  cat > ${puppetdb_default} <<PUPPETDBDELIM
JAVA_BIN="/usr/bin/java"
JAVA_ARGS="${puppetdb_jvm_size} -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/var/log/puppetdb/puppetdb-oom.hprof "
USER="puppetdb"
GROUP="puppetdb"
INSTALL_DIR="/opt/puppetlabs/server/apps/puppetdb"
CONFIG="/etc/puppetlabs/puppetdb/conf.d"
BOOTSTRAP_CONFIG="/etc/puppetlabs/puppetdb/bootstrap.cfg"
SERVICE_STOP_RETRIES=60
PUPPETDBDELIM

  cat > /etc/puppetlabs/puppetdb/conf.d/database.ini <<PUPPETDBDELIM
[database]
classname = org.postgresql.Driver
subprotocol = postgresql
subname = //localhost:5432/puppetdb
username = puppetdb
password = ${postgresql_password}
# gc-interval = 60
log-slow-statements = 10
PUPPETDBDELIM

  # install plugin to connect puppet master to puppetdb
  cat > /etc/puppetlabs/puppet/puppetdb.conf <<DELIM
[main]
server_urls = https://${puppet_server_fqdn}:8081
DELIM
  execute "grep 'storeconfigs = true' /etc/puppetlabs/puppet/puppet.conf"
  if [[ $? -ne 0 ]]; then
    echo "storeconfigs = true" >> /etc/puppetlabs/puppet/puppet.conf
  fi
  execute "grep 'storeconfigs_backend = puppetdb' /etc/puppetlabs/puppet/puppet.conf"
  if [[ $? -ne 0 ]]; then
    echo "storeconfigs_backend = puppetdb" >> /etc/puppetlabs/puppet/puppet.conf
  fi
  execute "grep 'reports = store,puppetdb' /etc/puppetlabs/puppet/puppet.conf"
  if [[ $? -ne 0 ]]; then
    echo "reports = store,puppetdb" >> /etc/puppetlabs/puppet/puppet.conf
  fi

  # make PuppetDB the authoritative source for the inventory service.
  cat > /etc/puppetlabs/puppet/routes.yaml <<\DELIM
---
master:
 facts:
  terminus: puppetdb
  cache: yaml
DELIM
}

function start_puppetdb () {
  local service="puppetdb"
  local service_count
  service_count=$(pgrep -f java | grep -c $service)
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

function pause_till_puppetdb_starts () {
  print_info "Waiting till puppetdb start's up (timeout in 60 seconds)"
  timeout 60s bash -c '
while : ; do
 grep "PuppetDB finished starting" /var/log/puppetlabs/puppetdb/puppetdb.log &>/dev/null && break
 printf .
 sleep 1
done
echo ""
'
  if [ $? -eq 124 ]; then
    print_error "Raised Timeout waiting for puppetdb to listen"
    exit 22
  else
    print_info "PuppetDB started successfully"
  fi
}

####
## Main
####

declare puppet_server_setup
declare puppet_client_setup
declare puppetdb_setup
declare passenger_setup
declare auto_signing_enabled
declare puppetdb_jvm_size
declare postgresql_password
declare puppet_server_hostname
declare setup_puppet_cron_job
declare wait_for_puppetdb
declare force_restart

function usage () {
  script=$0
  cat <<USAGE
Syntax
$(basename "$script") -s -c -d -a -j -J {-Xmx512m|-Xmx256m} -P {psql_password} -H {ps_hostname} -h

-s: puppet server setup
-c: puppet client setup
-d: setup puppetdb for stored configurations and reports
-a: set up auto signing for the same clients belonging to same domain
-j: set up cron job for running puppet agent every 30 minutes otherwise starts puppet agent as service
-w: wait till puppetdb starts
-J: JVM Heap Size for puppetdb
-P: postgresql password for puppetdb|postgres user (default: puppetdb)
-H: puppet server hostname (required for agents setup)
-v: verbose output
-h: show help

Examples:
Install puppet server with all defaults:
$(basename "$script") -s
Install puppet server with puppetdb for stored configurations and reports:
$(basename "$script") -s -d
Install puppet client:
$(basename "$script") -c -H {puppet_server_hostname}

USAGE
  exit 1
}

function check_variables () {
  print_info "Checking command line & user-defined variables for any errors..."

  if [[ "$puppet_client_setup" = "true" ]]; then
    if [[ -z ${puppet_server_hostname} ]]; then
      print_error "Option puppet client setup (-c) requires to pass puppet server hostname using (-H)"
      echo
      usage
      exit 1
    fi
  fi
  if [[ "$puppetdb_setup" = "true" ]]; then
    if [[ -z ${puppetdb_jvm_size} ]]; then
      print_warning "PuppetDB JVM size not set, default value of '-Xmx192m' will be used"
      puppetdb_jvm_size="-Xmx192m"
    fi
    if [[ -z ${postgresql_password} ]]; then
      print_warning "Postgresql password for puppetdb user not set, default value of 'puppetdb' will be used"
      postgresql_password="puppetdb"
    fi
  fi
}

function main () {
  local start_time
  local end_time

  trap "kill 0" SIGINT SIGTERM EXIT

  # parse command line options
  while getopts J:P:H:scdajvwfh opts
  do
    case $opts in
      s)
        puppet_server_setup="true"
        ;;
      c)
        puppet_client_setup="true"
        ;;
      d)
        puppetdb_setup="true"
        ;;
      a)
        auto_signing_enabled="true"
        ;;
      j)
        setup_puppet_cron_job="true"
        ;;
      w)
        wait_for_puppetdb="true"
        ;;
      f)
        force_restart="true"
        ;;
      J)
        puppetdb_jvm_size=$OPTARG
        ;;
      P)
        postgresql_password=$OPTARG
        ;;
      H)
        puppet_server_hostname=$OPTARG
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
  start_time="$(date +%s)"
  get_system_info
  check_preqs
  stop_iptables
  stop_selinux
  if [[ "$puppet_server_setup" = "true" ]]; then
    install_puppet_server
    configure_puppet_server
    if [[ "$auto_signing_enabled" = "true" ]]; then
      configure_autosign_certificates
    fi
    start_puppet_server
    if [[ "$puppetdb_setup" = "true" ]]; then
        install_postgres
        configure_postgres
        start_postgres
        configure_postgres_users
        install_puppetdb
        configure_puppetdb
        start_puppetdb
        if [[ "$wait_for_puppetdb" = "true" ]]; then
          pause_till_puppetdb_starts
        fi
        stop_puppet_server
        start_puppet_server
    fi
    test_puppet_run
  elif [[ "$puppet_client_setup" = "true" ]]; then
    install_puppet_client
    configure_puppet_client
    if [[ "$setup_puppet_cron_job" = "true" ]]; then
      setup_puppet_client_cron_job
    else
      start_puppet_client
    fi
  else
    print_error "Invalid script options, try passing -s or -c option"
    usage
    exit 1
  fi
  end_time="$(date +%s)"
  print_info "Execution complete. Time took: $((end_time - start_time)) second(s)"
}

main "$@"
