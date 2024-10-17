#!/bin/bash

function run_cmd() {
    _CMD=$@
    log_msg "CMD" "$@"
    eval "${_CMD}" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        log_msg "OK"
        return 0
    else
        log_msg "FAIL"
        return 1
    fi
}

function log_msg() {
    _CMD_LOG="tee -a ${SCRIPT_LOG}/script_${TODAY}.log"
    _RUN_TODAY=$(date "+%y%m%d")
    _RUN_TIME=$(date "+%H:%M:%S.%3N")
  
    _LOG_TIME="${_RUN_TODAY} ${_RUN_TIME}"
    _LOG_TYPE=$1
    _LOG_MSG=$2

    # printf "%-*s | %s\n" ${STR_LEGNTH} "Server Serial" "Unknown" |tee -a ${LOG_FILE} >/dev/null
    case ${_LOG_TYPE} in
        "CMD"   ) printf "%s | %-*s | %s\n" "${_LOG_TIME}" 7 "${_LOG_TYPE}" "${_LOG_MSG}"   ;;
        "OK"    ) printf "%s | %-*s | %s\n" "${_LOG_TIME}" 7 "${_LOG_TYPE}" "command ok."   ;;
        "FAIL"  ) printf "%s | %-*s | %s\n" "${_LOG_TIME}" 7 "${_LOG_TYPE}" "command fail." ;;
        "INFO"  ) printf "%s | %-*s | %s\n" "${_LOG_TIME}" 7 "${_LOG_TYPE}" "${_LOG_MSG}"   ;;
        "WARR"  ) printf "%s | %-*s | %s\n" "${_LOG_TIME}" 7 "${_LOG_TYPE}" "${_LOG_MSG}"   ;;
        "SKIP"  ) printf "%s | %-*s | %s\n" "${_LOG_TIME}" 7 "${_LOG_TYPE}" "${_LOG_MSG}"   ;;
        "ERROR" ) printf "%s | %-*s | %s\n" "${_LOG_TIME}" 7 "${_LOG_TYPE}" "${_LOG_MSG}"   ;;
    esac
}

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
        if [ ! -f /etc/chrony/chrony.conf.org ]; then
            run_cmd "cp -p /etc/chrony/chrony.conf /etc/chrony/chrony.conf.org"
        else
        _RUN_TODAY=$(date "+%y%m%d")
        _RUN_TIME=$(date "+%H:%M:%S.%3N")
    
        _LOG_TIME="${_RUN_TODAY} ${_RUN_TIME}"
            read -p "Already file 

        fi

}






main() {
    [ $# -eq 0 ] && help_usage
    set_opts "$@"

    setup_config
    case ${MODE} in
        "install" )
            install_ntp
        ;;
        "remove"  ) echo "remote"  ; exit 0 ;;
        *         ) help_usage     ; exit 0 ;;
    esac
}
main $*