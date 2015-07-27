#!/bin/bash
#
# Author:: Ashrith Mekala (<ashrith@cloudwick.com>)
# Description:: Script to install chef server/client
# Supported OS:: CentOS, Redhat, Ubuntu
# Version: 0.1
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
webui_password=""
amqp_password=""
postgresql_password=""
chef_environment="_default"

####
## Configuration Variables (change these, only if you know what you are doing)
####
chef_server_version="11.0.10-1"
chef_client_version="11.8.2-1"
chef_server_ssl_port="443"

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
      os_version=$( cat `ls /etc/*release | grep "redhat\|SuSE"` | head -1 | awk '{ for(i=1; i<=NF; i++) { if ( $i ~ /[0-9]+/ ) { cnt=split($i, arr, "."); if ( cnt > 1) { print arr[1] } else { print $i; } break; } } }' | tr '[:upper:]' '[:lower:]' )
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

  for command in curl vim; do
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

function add_opscode_repo () {
  case "$os" in
    centos|redhat)
      add_epel_repo
      if [[ ! -f /etc/yum.repos.d/opscode-chef.repo ]]; then
        print_info "Adding opscode chef repo to yum repositories list..."
        cat > /etc/yum.repos.d/opscode-chef.repo <<EOFYUM
[opscode-chef]
name=Opcode Chef full-stack installers for EL${os_version} - \$basearch
baseurl=http://yum.opscode.com/el/${os_version}/\$basearch/
enabled=1
gpgcheck=1
gpgkey=http://apt.opscode.com/packages@opscode.com.gpg.key
EOFYUM
      execute "gpg --keyserver keys.gnupg.net --recv-keys 83EF826A"
      execute "gpg --export -a packages@opscode.com | sudo tee /etc/pki/rpm-gpg/RPM-GPG-KEY-opscode"
      execute "rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-opscode"
      execute "yum clean all"
      fi
      ;;
    ubuntu)
      if [[ ! -f /etc/apt/sources.list.d/opscode.list ]]; then
        print_info "Adding puppetlabs repo to apt sources list"
        cat > /etc/apt/sources.list.d/opscode.list <<EOFAPT
deb http://apt.opscode.com/ ${os_codename}-0.10 main
EOFAPT
        [[ ! -d /etc/apt/trusted.gpg.d ]] && mkdir -p /etc/apt/trusted.gpg.d
        execute "gpg --keyserver keys.gnupg.net --recv-keys 83EF826A"
        execute "gpg --export packages@opscode.com | sudo tee /etc/apt/trusted.gpg.d/opscode-keyring.gpg > /dev/null"
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

function check_if_chef_server_is_installed () {
  print_info "Checking to see if chef server is installed..."
  case "$os" in
    centos|redhat)
      execute "rpm -q chef-server"
      return $?
      ;;
    ubuntu)
      execute "dpkg --list | grep chef-server"
      return $?
      ;;
    *)
      print_error "$os is not supported yet."
      exit 1
      ;;
  esac
}

function download_chef_server_package () {
  local package_root="https://opscode-omnibus-packages.s3.amazonaws.com"
  case "$os" in
    centos|redhat)
      # https://opscode-omnibus-packages.s3.amazonaws.com/el/6/x86_64/chef-server-11.0.10-1.el6.x86_64.rpm
      local package_name="chef-server-${chef_server_version}.el${os_version}.x86_64.rpm"
      local package_path="${package_root}/el/${os_version}/x86_64/${package_name}"
      chef_server_package_path="/tmp/$package_name"
      if [[ ! -f $chef_server_package_path ]]; then
        print_info "Downloading chef server package..."
        execute "curl $package_path -o $chef_server_package_path"
        if [[ $? -ne 0 ]]; then
          print_error "Failed downloading chef-server package, stopping."
          exit 1
        fi
      fi
      ;;
    ubuntu)
      # https://opscode-omnibus-packages.s3.amazonaws.com/ubuntu/12.04/x86_64/chef-server_11.0.10-1.ubuntu.12.04_amd64.deb
      local package_name="chef-server_${chef_server_version}.ubuntu.${os_version}.04_amd64.deb"
      local package_path="${package_root}/ubuntu/12.04/x86_64/${package_name}"
      chef_server_package_path="/tmp/$package_name"
      execute "curl $package_path -o /tmp/$package_name"
      if [[ ! -f $chef_server_package_path ]]; then
        print_info "Downloading chef server package..."
        execute "curl $package_path -o $chef_server_package_path"
        if [[ $? -ne 0 ]]; then
          print_error "Failed downloading chef-server package, stopping."
          exit 1
        fi
      fi
      ;;
    *)
    print_error "$os is not yet supported"
    exit 1
  esac
}

function install_chef_server () {
  check_if_chef_server_is_installed
  if [[ $? -eq 0 ]]; then
    print_info "Package chef-server is already installed. Skipping installation step."
    return
  fi
  # add_opscode_repo
  if [[ "xx86_64" != "x${os_arch}" ]]; then
    print_error "Chef server packages are only available for x86_64. Stopping."
    exit 1
  fi
  download_chef_server_package
  print_info "Installing chef-server package from $chef_server_package_path"
  case "$os" in
    centos|redhat)
      execute "rpm -Uvh $chef_server_package_path"
      if [[ $? -ne 0 ]]; then
        print_error "Failed installing/updating chef server package"
        exit 2
      else
        rm -f $chef_server_package_path
      fi
      ;;
    ubuntu)
      execute "dpkg -i $chef_server_package_path"
      if [[ $? -ne 0 ]]; then
        print_error "Failed installing/updating chef server package"
        exit 2
      else
        rm -f $chef_server_package_path
      fi
      ;;
    *)
      print_error "$os is not supported yet."
      exit 1
      ;;
  esac
}

function configure_chef_server () {
  local primary_net=$(ip route list match 0.0.0.0 | awk 'NR==1 {print $5}')
  local primary_net_ip=$(ip addr show dev ${primary_net} | awk 'NR==3 {print $2}' | cut -d '/' -f1)
  local chef_url="https://${primary_net_ip}:${chef_server_ssl_port}"
  print_info "Configuring chef-server..."
  if [[ ! -e "/etc/chef-server/chef-server.rb" ]]; then
    [[ ! -d /etc/chef-server ]] && mkdir -p /etc/chef-server
    cat > /etc/chef-server/chef-server.rb <<CHEFEOF
node.override["chef_server"]["chef-server-webui"]["web_ui_admin_default_password"] = "${webui_password}"
node.override["chef_server"]["rabbitmq"]["password"] = "${amqp_password}"
node.override["chef_server"]["postgresql"]["sql_password"] = "${postgresql_password}"
node.override["chef_server"]["postgresql"]["sql_ro_password"] = "${postgresql_password}"
node.override["chef_server"]["nginx"]["url"] = "${chef_url}"
node.override["chef_server"]["nginx"]["ssl_port"] = ${ssl_port}
node.override["chef_server"]["nginx"]["non_ssl_port"] = 80
node.override["chef_server"]["nginx"]["enable_non_ssl"] = true
node.override["chef_server"]["bookshelf"]["url"] = "${chef_url}"
if (node["memory"]["total"].to_i / 4) > ((node["chef_server"]["postgresql"]["shmmax"].to_i / 1024) - 2097152)
  # guard against setting shared_buffers > shmmax on hosts with installed RAM > 64GB
  # use 2GB less than shmmax as the default for these large memory machines
  node.override["chef_server"]["postgresql"]["shared_buffers"] = "14336MB"
else
  node.override["chef_server"]["postgresql"]["shared_buffers"] = "#{(node['memory']['total'].to_i / 4) / (1024)}MB"
end
node.override["erchef"]["s3_url_ttl"] = 3600
CHEFEOF
    execute "chef-server-ctl reconfigure"
    if [[ $? -ne 0 ]]; then
      print_error "Failed configuring chef-sever, stopping."
      exit 1
    fi
  fi
}

function test_chef_server () {
  print_info "Testing chef server deployment..."
  execute "chef-server-ctl test"
  if [[ $? -ne 0 ]]; then
    print_error "chef-server is not running as expected, stopping."
    exit 1
  fi
}

function check_if_chef_server_is_running () {
  local service_count=$(ps -ef | grep -v grep | grep chef-server-webui | wc -l)
  local service_stauts=$(chef-server-ctl status | grep chef-server-webui | awk '{print $1}')
  if [[ $service_count -gt 0 && "$service_stauts" =~ run ]]; then
    return 0 # print_info "Chef server is running as expected"
  else
    return 1
  fi
}

function safe_configure_chef_server () {
  check_if_chef_server_is_running
  if [[ $? -ne 0 ]]; then
    print_warning "Chef server service is not running, attempting reconfigure & restart..."
    configure_chef_server
    execute "chef-server-ctl restart"
    if [[ $? -ne 0 ]]; then
      print_error "Failed restarting chef-server service(s), stopping."
      exit 1
    fi
    test_chef_server
  else
    print_info "Chef server is running as expected, skipping start step."
  fi
}

function setup_admin_user () {
  if [[ ! -d ${HOME}/.chef ]]; then
    print_info "Setting up admin user account"
    execute "mkdir ${HOME}/.chef"
    case "$os" in
      centos|redhat)
        execute "cp /etc/chef-server/{chef-validator.pem,admin.pem} ${HOME}/.chef"
        execute "chown -R $USER ${HOME}/.chef"
        execute "echo 'export PATH="/opt/chef-server/embedded/bin:$PATH"' >> ~/.bash_profile && source ~/.bash_profile"
        ;;
      ubuntu)
        execute "cp /etc/chef-server/{chef-validator.pem,admin.pem} ${HOME}/.chef"
        execute "chown -R $USER $HOME/.chef"
        ;;
      *)
        print_error "$os is not supported yet."
        exit 1
        ;;
    esac
  fi
}

function configure_knife () {
  local primary_net=$(ip route list match 0.0.0.0 | awk 'NR==1 {print $5}')
  local primary_net_ip=$(ip addr show dev ${primary_net} | awk 'NR==3 {print $2}' | cut -d '/' -f1)
  local chef_url="https://${primary_net_ip}:${chef_server_ssl_port}"
  if [[ ! -f ${HOME}/.chef/knife.rb ]]; then
    print_info "Configuring knife..."
    setup_admin_user
    /opt/chef-server/embedded/bin/knife configure <<KNIFEEOF
${HOME}/.chef/knife.rb
${chef_url}
admin
chef-validator
${HOME}/.chef/chef-validator.pem
KNIFEEOF
  execute "ln -sf /opt/chef-server/embedded/bin/knife /usr/bin/knife"
  fi
}

function check_if_chef_client_is_installed () {
  print_info "Checking to see if chef agent is installed..."
  case "$os" in
    centos|redhat)
      execute "rpm -q chef"
      return $?
      ;;
    ubuntu)
      execute "dpkg --list | grep chef"
      return $?
      ;;
    *)
      print_error "$os is not supported yet."
      exit 1
      ;;
  esac
}

function install_chef_client () {
  check_if_chef_client_is_installed
  if [[ $? -eq 0 ]]; then
    print_info "Package chef is already installed. Skipping installation step."
    return
  fi
  print_info "Installing chef agent package..."
  execute "curl -skS -L https://www.opscode.com/chef/install.sh | bash -s - -v ${chef_client_version}"
  if [[ $? -ne 0 ]]; then
    print_error "Failed installing chef agent, stopping."
    exit 1
  fi
}

function configure_chef_client () {
  local chef_server_ip=$1
  local chef_url="https://${chef_server_ip}:${chef_server_ssl_port}"
  local environment=${chef_environment:-_default}
  print_info "Configuring chef agent..."
  # requires /etc/chef/validation.pem from chef-server
  if [[ ! -f /etc/chef/validation.pem ]]; then
    print_info "Trying ssh to get chef validation private key..."
    execute "scp $chef_server_ip:/etc/chef-server/chef-validator.pem /tmp/validation.pem"
    if [[ $? -ne 0 ]]; then
      print_warning "Cannot scp 'chef-validator.pem' from chef-server to this machine.
      Copy the 'validation.pem' from server located at '/etc/chef-server/chef-validator.pem'
      to the client being configured to path '/etc/chef/validation.pem'"
    else
      [[ ! -d /etc/chef ]] && execute "mkdir -p /etc/chef"
      execute "cp /tmp/validation.pem /etc/chef/validation.pem"
    fi
  fi
  cat > /etc/chef/client.rb <<EOF2
Ohai::Config[:disabled_plugins] = ["passwd"]

chef_server_url "${chef_url}"
chef_environment "${environment}"
EOF2

cat <<EOF2 > /etc/chef/knife.rb
chef_server_url "${chef_url}"
chef_environment "${environment}"
node_name "${1}"
EOF2
}

####
## Main
####

declare chef_server_setup
declare chef_client_setup
declare chef_server_hostname
declare solr_jvm_size
declare chef_workstation_setup
declare chef_server_package_path

function usage () {
  script=$0
  cat <<USAGE
Syntax
`basename ${script}` -s -c -w -J {-Xmx512m|-Xmx256m} -H {cs_hostname} -h

-s: chef server setup
-c: chef client setup
-w: Chef workstation setup
-J: JVM Heap Size for solr
-H: chef server ip (required for chef client setup)
-v: verbose output
-h: show help

USAGE
  exit 1
}

function check_variables () {
  print_info "Checking command line & user-defined variables for any errors..."

  if [[ -z $chef_server_version ]]; then
    print_error "Variable 'chef_server_version' is required, set this variable in the script"
    exit 1
  fi
  if [[ -z $chef_server_ssl_port ]]; then
    print_error "Variable 'chef_server_ssl_port' is required, set this variable in the script"
    exit 1
  fi
  if [[ -z $webui_password ]]; then
    webui_password=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c ${1:-10} | xargs)
    print_warning "'webui_password' for chef-server not set, defaulting to ${webui_password}"
  fi
  if [[ -z $amqp_password ]]; then
    amqp_password=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c ${1:-10} | xargs)
    print_warning "'amqp_password' for chef-server not set, defaulting to ${amqp_password}"
  fi
  if [[ -z $postgresql_password ]]; then
    postgresql_password=$(tr -dc A-Za-z0-9_ < /dev/urandom | head -c ${1:-10} | xargs)
    print_warning "'postgresql_password' for chef-server not set, defaulting to ${postgresql_password}"
  fi
  if [[ "$chef_client_setup" = "true" ]]; then
    if [[ -z $chef_server_hostname ]]; then
      print_error "Option chef client setup (-c) requires to pass chef server hostname using (-H)"
      echo
      usage
      exit 1
    fi
  elif [[ "$chef_server_setup" = "true" ]]; then
    if [[ -z $solr_jvm_size ]]; then
      print_warning "Solr JVM size not set, default value of '-Xmx192m' will be used"
      solr_jvm_size="-Xmx192m"
    fi
  else
    print_error "Invalid script options, should wither pass -s or -c option"
    usage
    exit 1
  fi
}

function main () {
  trap "kill 0" SIGINT SIGTERM EXIT

  # parse command line options
  while getopts J:H:scwvh opts
  do
    case $opts in
      s)
        chef_server_setup="true"
        ;;
      c)
        chef_client_setup="true"
        ;;
      J)
        solr_jvm_size=$OPTARG
        ;;
      H)
        chef_server_hostname=$OPTARG
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
  if [[ "$chef_server_setup" = "true" ]]; then
    install_chef_server
    safe_configure_chef_server
    configure_knife
  elif [[ "$chef_client_setup" = "true" ]]; then
    install_chef_client
    configure_chef_client $chef_server_hostname
  fi
  local end_time="$(date +%s)"
  print_info "Execution complete. Time took: $((end_time - start_time)) second(s)"
}

main $@
