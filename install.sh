#!/bin/bash

# https://medium.com/@rohitdoshi9/automated-backup-and-rotation-in-linux-12ea9c545f12

SCRIPT_DIR=$(dirname $(realpath $0))

for _FILE in $(ls ${SCRIPT_DIR}/lib); do
    source ${SCRIPT_DIR}/lib/${_FILE}
    echo "source ${SCRIPT_DIR}/lib/${_FILE}"
done

if [ ! -d ${SCRIPT_DIR_LOG} ]; then
    run_cmd "mkdir ${SCRIPT_DIR_LOG}"
fi

function help_usage() {
    cat <<EOF
Usage: $0 [Options]
Options:
-i, --install             : Install Openstack
-r, --remove              : Remove Openstack
-c, --config [ Path ]     : Openstack setup config file path
EOF
    exit 0
}

function set_opts() {
    arguments=$(getopt --options c:hir \
    --longoptions config:,help,install,remove \
    --name $(basename $0) \
    -- "$@")

    eval set -- "${arguments}"
    while true; do
        case "$1" in
            -i | --install  ) MODE="install"; shift   ;;
            -r | --remove   ) MODE="remove" ; shift   ;;
            -c | --config   ) CONF_PATH=$2  ; shift 2 ;;
            -h | --help     ) help_usage              ;;
            --              ) shift         ; break   ;;
            ?               ) help_usage              ;;
        esac
    done

    shift $((OPTIND-1))
}

function install_ntp() {
    run_cmd "apt install -y chrony"
    if [ $? -eq 0 ]; then
        if [ ! -d /etc/chrony/chrony_bak ]; then
            run_cmd "mkdir /etc/chrony/chrony_bak"
        fi

        if [ ! -f /etc/chrony/chrony.conf.org ]; then
            run_cmd "cp -p /etc/chrony/chrony.conf /etc/chrony/chrony_bak/chrony.conf.org"
        fi
        
        if [ ! -f /etc/chrony/chrony.conf.bak ]; then
            _NUM_BAKCUPS=$(ls -l /etc/chrony/chrony_bak |grep -c chrony.conf.bak.*)
            run_cmd "cp -p /etc/chrony/chrony.conf /etc/chrony/chrony_bak/chrony.conf.bak${_NUM_BAKCUPS}"
            run_cmd "cp -f /etc/chrony/chrony_bak/chrony.conf.org /etc/chrony/chrony.conf"
        fi
    fi

    run_cmd "sed -i 's/^pool/#&/g' /etc/chrony/chrony.conf"
    run_cmd "cat <<EOF >>/etc/chrony/chrony.conf
server 0.kr.pool.ntp.org prefer iburst minpoll 4 maxpoll 4
allow ${OPENSTACK_MGMT_NET}
EOF"
}

main() {
    [ $# -eq 0 ] && help_usage
    set_opts "$@"

    if [ -n ${CONF_PATH} ]; then
        if [ -f ${CONF_PATH} ]; then
            source ${CONF_PATH}
        else
            log_msg "ERROR" "Not found config file [ ${CONF_PATH} ]."
            eixt 1
        fi
    else
        log_msg "ERROR" "Reserved config file option"
        eixt 1
    fi

    OS_NAME=$(grep '^NAME=' /etc/os-release |cut -d'=' -f2)
    OS_VERSION=$(grep '^VERSION_ID=' /etc/os-release |cut -d'=' -f2)

    # case ${OS_NAME} in
    #     ubuntu | Ubuntu ) ;;
    #     Centos | CentOS | Rocky Linux ) ;;
    # esac
    install_ntp
}

main $*