#!/bin/bash
# https://medium.com/@rohitdoshi9/automated-backup-and-rotation-in-linux-12ea9c545f12

SCRIPT_DIR=$(dirname $(realpath $0))

for _FILE in $(ls ${SCRIPT_DIR}/lib); do
    source ${SCRIPT_DIR}/lib/${_FILE}
done

function help_usage() {
    cat <<EOF
Usage: $0 [Options]
Options:
-i, --install             : Install Openstack
-r, --remove              : Remove Openstack
-m, --mode   [ controller or compute ] : Openstack install mode
-c, --config [ Path ]     : Openstack setup config file path
EOF
    exit 0
}

function set_opts() {
    arguments=$(getopt --options c:m:hir \
    --longoptions config:,mode:,help,install,remove \
    --name $(basename $0) \
    -- "$@")

    eval set -- "${arguments}"
    while true; do
        case "$1" in
            -i | --install  ) MODE="install"; shift   ;;
            -r | --remove   ) MODE="remove" ; shift   ;;
            -m | --mode     ) SVR_MODE=$2   ; shift 2 ;;
            -c | --config   ) CONF_PATH=$2  ; shift 2 ;;
            -h | --help     ) help_usage              ;;
            --              ) shift         ; break   ;;
            ?               ) help_usage              ;;
        esac
    done

    shift $((OPTIND-1))
}

function install_ntp() {
    check_pkg "chrony"
    if [ $? -eq 0 ]; then
        if [ ! -f /etc/chrony/chrony.conf.org ]; then
            run_cmd "cp -p /etc/chrony/chrony.conf /etc/chrony/chrony_bak/chrony.conf.org"
        fi

        run_cmd "sed -i 's/^pool/#&/g' /etc/chrony/chrony.conf"
        run_cmd "cat <<EOF >>/etc/chrony/chrony.conf

server 0.kr.pool.ntp.org prefer iburst minpoll 4 maxpoll 4
allow ${OPENSTACK_MGMT_NET}
EOF"
        run_cmd "systemctl enable --now chrony"
        run_cmd "systemctl restart chrony"
        return 0
    else
        return 0
    fi
}

function install_openstack_client() {
    _OPENSTACK_VERSION=$(echo "${OPENSTACK_VERSION}" |tr '[A-Z]' '[a-z]')
    case ${PKG_CMD[0]} in
        yum )
            run_cmd "${PKG_CMD[2]}-${_OPENSTACK_VERSION}"
        ;;
        apt )
            if [[ ${OS_VERSION} =~ "22.04" ]]; then
                log_msg "SKIP" "Already Openstack(${_OPENSTACK_VERSION}) repo suported Ubuntu 22.04."
            else
                run_cmd "${PKG_CMD[2]}:${_OPENSTACK_VERSION}"
            fi
        ;;
    esac

    if [ $? -eq 0 ]; then
        check_pkg "python3-openstackclient"
        if [ $? -eq 0 ]; then
            return 0
        fi
    else
        log_msg "ERROR" "Fail add repository."
        exit 1
    fi
}

function install_mysql() {
    if [ ${SVR_MODE} == "controller" ]; then
        case ${PKG_CMD[0]} in
            yum )
                # run_cmd "${PKG_CMD[2]}-${_OPENSTACK_VERSION}"
                log_msg "ERRIR" "No supported script. for upeer of Ubuntu 20.04 "
                exit 1
            ;;
            apt )
                if [[ ${OS_VERSION} =~ "18.04" ]] || [[ ${OS_VERSION} =~ "16.04" ]]; then
                    log_msg "ERRIR" "No supported script. for upeer of Ubuntu 20.04 "
                    exit 1
                elif [[ ${OS_VERSION} =~ 2[0-4].04 ]]; then
                    check_pkg "mariadb-server" "python3-pymysql"
                else
                    log_msg "ERRIR" "No supported script. for upeer of Ubuntu 20.04 "
                    exit 1
                fi
            ;;
        esac
    elif [ ${SVR_MODE} == "compute" ]; then
        log_msg "SKIP" "Skip install mysql."
        return 0
    else
        log_msg "FAIL" "Please check option -m [ supported 'controller' or 'compute' ]."
        help_usage
        return 0 
    fi

    if [ $? -eq 0 ]; then
        run_cmd "cat <<\EOF >/etc/mysql/mariadb.conf.d/99-openstack.cnf
[mysqld]
bind-address = ${OPENSTACK_CONTROLLER_IP}

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF"
        if [ $? -eq 0 ]; then
            return 0
        else
            log_msg "ERROR" "Faile config setup [/etc/mysql/mariadb.conf.d/99-openstack.cnf] error code \'$?\'."
            exit 1
        fi
    fi
}

main() {
    [ $# -eq 0 ] && help_usage
    set_opts "$@"

    if [[ -n ${CONF_PATH} ]] && [[ -n ${SVR_MODE} ]]; then
        if [ -f ${CONF_PATH} ]; then
            source ${CONF_PATH}
            if [ ! -d ${SCRIPT_DIR_LOG} ]; then
                run_cmd "mkdir ${SCRIPT_DIR_LOG}"
            fi
        else
            log_msg "ERROR" "Not found config file [ ${CONF_PATH} ]."
            eixt 1
        fi
    else
        log_msg "ERROR" "Reserved [ -c and -m ] option."
        help_usage
        exit 1
    fi

    OS_NAME=$(grep '^NAME=' /etc/os-release |cut -d'=' -f2)
    OS_VERSION=$(grep '^VERSION_ID=' /etc/os-release |cut -d'=' -f2)

    case ${OS_NAME} in
        *centos* | *Centos* | *CentOS* | *rocky* | *Rocky* )
            PKG_CMD=('yum' 'rpm' "yum entos-release-openstack")
        ;;
        *ubuntu* | *Ubuntu* )
            PKG_CMD=('apt' 'dpkg' "add-apt-repository cloud-archive")
        ;;
    esac

    install_ntp
    install_openstack_client
    install_mysql
}

main $*