#!/usr/bin/env bash

case $1 in
validate)
  ;;
install)
  ;;
create)
  ;;
*)
  echo "Usage: $(basename $0) <command> <command args>"  >&2
  echo " Commands:" >&2
  echo "  validate /path/to/mcollective/config" >&2
  echo "    - Validate all required mcollective plugin files exist" >&2
  echo "  install /path/to/mcollective/config /path/where/script/can/clone/missing/repositories" >&2
  echo "    - Attempt to put all required mco plugins into the mco libdir listed in your mcollective config" >&2
  echo "      Requires the following environment variables to be set: REPO_PUPPET" >&2
  echo "  create /path/to/mcollective/config" >&2
  echo "    - Create an example mcollective config to fill out" >&2
  exit
esac

set -euo pipefail

if [ "$#" -lt 2 ]; then
  echo "Usage: $(basename $0) <command> </path/to/mcollective/config/file> <additional arguments>"  >&2
  echo "If you don't have one you can generate one to fill out with: $(basename $0) create ~/.mcollective" >&2
  exit 1
fi

COMMAND=$1
MCO_CONFIG_FILE=$2

declare -A FROM
FROM[mcollective/util/puppetng.rb]='mcollective-puppetng'
FROM[mcollective/util/puppetng/managed_puppet_run.rb]='mcollective-puppetng'
FROM[mcollective/util/puppetng/colorize.rb]='mcollective-puppetng'
FROM[mcollective/util/puppetng/redis_observer.rb]='mcollective-puppetng'
FROM[mcollective/util/puppetng/puppet_run_registry.rb]='mcollective-puppetng'
FROM[mcollective/application/puppetng.rb]='mcollective-puppetng'
FROM[mcollective/discovery/mongorest.ddl]='puppet'
FROM[mcollective/discovery/mongorest.rb]='puppet'
FROM[mcollective/agent/puppetng.rb]='mcollective-puppetng'
FROM[mcollective/agent/puppetng.ddl]='mcollective-puppetng'
FROM[mcollective/agent/computenodestorage.ddl]='provisioning-tools'
FROM[mcollective/agent/libvirt.ddl]='puppet'
FROM[mcollective/agent/lvm.ddl]='puppet'
FROM[mcollective/agent/computenode.ddl]='provisioning-tools'
FROM[mcollective/agent/k8ssecret.ddl]='puppet'
FROM[mcollective/agent/nagsrv.ddl]='puppet'
FROM[mcollective/agent/puppetca.ddl]='puppet'
FROM[mcollective/agent/service.ddl]='puppet'
FROM[mcollective/agent/hostcleanup.ddl]='puppet'
FROM[mcollective/agent/hpilo.ddl]='puppet'

case $COMMAND in
validate)
  if [ ! -e "$MCO_CONFIG_FILE" ]; then
    echo "mcollective config file '${1}' does not exist"
    echo "If you don't have one you can generate one to fill out with: $(basename $0) create ~/.mcollective" >&2
    exit 1
  fi

  LIBDIR=$(grep -Fr libdir $MCO_CONFIG_FILE | tail -n1 | awk -F '=' '{print $2}' | sed 's/^ *//' | sed 's/ *$//')
  got_all_files=true

  for file in "${!FROM[@]}"; do
    if [ ! -e "${LIBDIR}/${file}" ]; then
      echo "File '${LIBDIR}/${file}' does not exist. It should come from '${FROM[$file]}'" >&2
      got_all_files=false
    fi
  done

  if ! $got_all_files; then
    echo "You should fix all of the above files." >&2
    echo "You can do that with: $(basename $0) install /path/to/mcollective/config /path/where/script/can/clone/missing/repositories" >&2
    echo "You must also set the following environment variables to the relevant git repository" >&2
    echo "REPO_PUPPET" >&2
    exit 1
  else
    echo "You appear to have all of the required mcollective plugins in your mcollective libdir." >&2
  fi
  ;;
install)
  if [ ! -e "$MCO_CONFIG_FILE" ]; then
    echo "mcollective config file '${1}' does not exist"
    echo "If you don't have one you can generate one to fill out with: $(basename $0) create ~/.mcollective" >&2
    exit 1
  fi

  if [ "$#" -ne 3 ]; then
    echo "Usage: $(basename $0) ${COMMAND} ${MCO_CONFIG_FILE} /path/where/script/can/clone/missing/repositories"  >&2
    echo "You must also set the following environment variables to the relevant git URL to clone from" >&2
    echo "REPO_PUPPET" >&2
    exit 1
  fi

  INSTALL_PATH=$3
  LIBDIR=$(grep -Fr libdir $MCO_CONFIG_FILE | tail -n1 | awk -F '=' '{print $2}' | sed 's/^ *//' | sed 's/ *$//')

  if [ -z ${REPO_PUPPET:-} ]; then
    echo "Usage: $(basename $0) ${COMMAND} ${MCO_CONFIG_FILE} ${INSTALL_PATH}"  >&2
    echo "You must also set the following environment variables to the relevant git URL to clone from" >&2
    echo "REPO_PUPPET" >&2
    exit 1
  fi

  declare -A REPOS
  REPOS[puppet]=${REPO_PUPPET}
  REPOS[mcollective-puppetng]=${REPO_MCO_PUPPETNG:-https://github.com/IG-Group/mcollective-puppetng.git}
  REPOS[provisioning-tools]=${REPO_PROV_TOOLS:-https://github.com/tim-group/provisioning-tools.git}
  declare -A REPO_CLONE_DIRS
  REPO_CLONE_DIRS[puppet]=${CLONE_DIR_NAME_PUPPET:-puppet}
  REPO_CLONE_DIRS[mcollective-puppetng]=${CLONE_DIR_NAME_MCO_PUPPETNG:-mcollective-puppetng}
  REPO_CLONE_DIRS[provisioning-tools]=${CLONE_DIR_NAME_PROV_TOOLS:-provisioning-tools}
  declare -A REPO_PATH
  REPO_PATH[mcollective/util/puppetng.rb]='mcollective/util/puppetng.rb'
  REPO_PATH[mcollective/util/puppetng/managed_puppet_run.rb]='mcollective/util/puppetng/managed_puppet_run.rb'
  REPO_PATH[mcollective/util/puppetng/colorize.rb]='mcollective/util/puppetng/colorize.rb'
  REPO_PATH[mcollective/util/puppetng/redis_observer.rb]='mcollective/util/puppetng/redis_observer.rb'
  REPO_PATH[mcollective/util/puppetng/puppet_run_registry.rb]='mcollective/util/puppetng/puppet_run_registry.rb'
  REPO_PATH[mcollective/application/puppetng.rb]='mcollective/application/puppetng.rb'
  REPO_PATH[mcollective/discovery/mongorest.ddl]='modules/mcollective/files/mcollective/discovery/mongorest.ddl'
  REPO_PATH[mcollective/discovery/mongorest.rb]='modules/mcollective/files/mcollective/discovery/mongorest.rb'
  REPO_PATH[mcollective/agent/puppetng.rb]='mcollective/agent/puppetng.rb'
  REPO_PATH[mcollective/agent/puppetng.ddl]='mcollective/agent/puppetng.ddl'
  REPO_PATH[mcollective/agent/computenodestorage.ddl]='mcollective/agent/computenodestorage.ddl'
  REPO_PATH[mcollective/agent/libvirt.ddl]='modules/mcollective/files/mcollective/agent/libvirt.ddl'
  REPO_PATH[mcollective/agent/computenode.ddl]='mcollective/agent/computenode.ddl'
  REPO_PATH[mcollective/agent/k8ssecret.ddl]='modules/mcollective/files/mcollective/agent/k8ssecret.ddl'
  REPO_PATH[mcollective/agent/lvm.ddl]='modules/mcollective/files/mcollective/agent/lvm.ddl'
  REPO_PATH[mcollective/agent/nagsrv.ddl]='modules/mcollective/files/mcollective/agent/nagsrv.ddl'
  REPO_PATH[mcollective/agent/puppetca.ddl]='modules/mcollective/files/mcollective/agent/puppetca.ddl'
  REPO_PATH[mcollective/agent/service.ddl]='modules/mcollective/files/mcollective/agent/service.ddl'
  REPO_PATH[mcollective/agent/hostcleanup.ddl]='modules/mcollective/files/mcollective/agent/hostcleanup.ddl'
  REPO_PATH[mcollective/agent/hpilo.ddl]='./modules/mcollective/files/mcollective/agent/hpilo.ddl'

  for file in "${!FROM[@]}"; do
    if [ ! -e "${LIBDIR}/${file}" ]; then
      echo "Need file ${LIBDIR}/${file}."
      pushd $LIBDIR >/dev/null
        mkdir -p $(dirname ${file})
        if [ ! -d $INSTALL_PATH/${REPO_CLONE_DIRS[${FROM[$file]}]} ]; then
          echo "Cloning ${FROM[$file]} repo from ${REPOS[${FROM[$file]}]} into $INSTALL_PATH/${REPO_CLONE_DIRS[${FROM[$file]}]}"
          git clone ${REPOS[${FROM[$file]}]} $INSTALL_PATH/${REPO_CLONE_DIRS[${FROM[$file]}]}
        fi
        echo "Symlinking $INSTALL_PATH/${REPO_CLONE_DIRS[${FROM[$file]}]}/${REPO_PATH[$file]} to ${LIBDIR}/${file}"
        ln -s $INSTALL_PATH/${REPO_CLONE_DIRS[${FROM[$file]}]}/${REPO_PATH[$file]} $file
      popd > /dev/null
    fi
  done

  echo "Success. To be sure everything is OK you should probably run: $(basename $0) validate $MCO_CONFIG_FILE"
  ;;
create)
  if [ -e "$MCO_CONFIG_FILE" ]; then
    echo "Cannot create mcollective config file '${MCO_CONFIG_FILE}' as it already exists." >&2
    exit 1
  fi

  echo "main_collective = mcollective

libdir = __PATH_WHERE_MCO_PLUGINS_SHOULD_BE_FOUND__
logfile = /dev/null
loglevel = info

# Plugins
securityprovider = ssl
plugin.ssl_server_public = _PATH_TO_SERVER_PUBLIC_CERT___
plugin.ssl_client_public = __PATH_TO_USERS_PUBLIC_CERT__
plugin.ssl_client_private = __PATH_TO_USERS_PRIVATE_CERT__

connector = rabbitmq
plugin.rabbitmq.pool.size = 1
plugin.rabbitmq.initial_reconnect_delay = 0.01
plugin.rabbitmq.max_reconnect_delay = 5
plugin.rabbitmq.use_exponential_back_off = true
plugin.rabbitmq.back_off_multiplier = 2
plugin.rabbitmq.max_reconnect_attempts = 0
plugin.rabbitmq.randomize = false
plugin.rabbitmq.timeout = -1
plugin.rabbitmq.connect_timeout = 3

plugin.rabbitmq.pool.1.host = __MCO_BROKER_SERVER_NAME__
plugin.rabbitmq.pool.1.port = 6163
plugin.rabbitmq.pool.1.user = mcollective
plugin.rabbitmq.pool.1.password = __MCO_BROKER_PASSWORD__
plugin.rabbitmq.pool.1.ssl = false

default_discovery_method=mongorest
plugin.discovery.mongorest.host=__MONGO_REST_SERVER_NAME__
# A host has to be gone for an entire day before we "forget" about it
plugin.discovery.mongorest.criticalage=86400

plugin.puppetng.exit_if_exceed_concurrency = 8

direct_addressing = 1
direct_addressing_threshold = 5" > "${MCO_CONFIG_FILE}"
  echo "Success. Please edit '${MCO_CONFIG_FILE}' and configure the required settings."
  echo "Pay particular attention to 'libdir'. Ensure this directory exists if you next plan"
  echo "to run $(basename $0) install"
  ;;
esac
