#!/bin/bash
SCRIPT_DIR=$(dirname "$0")
source ${SCRIPT_DIR}/lib/*

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

main() {
    [ $# -eq 0 ] && help_usage
    set_opts "$@"

    log_msg "CMD" "test"
    exit 0
}
main $*