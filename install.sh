#!/bin/bash
# https://medium.com/@rohitdoshi9/automated-backup-and-rotation-in-linux-12ea9c545f12
# https://bertvv.github.io/notes-to-self/2015/11/16/automating-mysql_secure_installation/

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
                check_pkg "mariadb-server"
                # remove "mariadb-common"
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
                        run_cmd "systemctl enable --now mysqld"
                        if [ $? -eq 0 ]; then
                            run_cmd "systemctl restart mysqld"
                            if [ $? -eq 0 ]; then
                                run_cmd "mysql -uroot mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASS}';\""
                                run_cmd "mysql -uroot -p'${DB_PASS}' mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASS}';\""
                                if [ $? -eq 0 ]; then
                                    _CMD=(
                                        "DELETE FROM mysql.user WHERE User='';"
                                        "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
                                        "DROP DATABASE IF EXISTS test;"
                                        "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
                                        "FLUSH PRIVILEGES;"
                                    )
                                    for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
                                        run_cmd "mysql -uroot -p'${DB_PASS}' mysql -e \"${_CMD[${_IDX}]}\""
                                        if [ $? -eq 0 ]; then
                                            continue
                                        else
                                            exit 1
                                        fi
                                    done
                                    return 0
                                else
                                    exit 1
                                fi
                            fi
                        else
                            log_msg "ERROR" "Faile start-up service."
                            exit 1
                        fi
                    else
                        log_msg "ERROR" "Faile config setup [/etc/mysql/mariadb.conf.d/99-openstack.cnf] error code \'$?\'."
                        exit 1
                    fi
                fi
            else
                log_msg "ERRIR" "No supported script. for upeer of Ubuntu 20.04 "
                exit 1
            fi
        ;;
    esac
}

function install_mysql_python() {
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
                check_pkg "python3-pymysql"

                if [ $? -eq 0 ]; then
                    return 0
                fi
            else
                log_msg "ERRIR" "No supported script. for upeer of Ubuntu 20.04 "
                exit 1
            fi
        ;;
    esac
}

function install_rabbitmq() {
    check_pkg "rabbitmq-server"
    if [ $? -eq 0 ]; then
        run_cmd "rabbitmqctl add_user openstack '${RABBIT_PASS}'"
        run_cmd "rabbitmqctl authenticate_user openstack '${RABBIT_PASS}' |grep -q Success"
        if [ $? -eq 0 ]; then
            run_cmd "rabbitmqctl set_permissions openstack \".*\" \".*\" \".*\""
            if [ $? -eq 0 ]; then
                run_cmd "systemctl enable --now rabbitmq-server"
                if [ $? -eq 0 ]; then
                    run_cmd "systemctl start rabbitmq-server"
                    if [ $? -eq 0 ]; then
                        return 0
                    fi
                else
                    exit 1
                fi
            else
                exit 1
            fi
        else
            exit 1
        fi
    else
        return 0
    fi
}

function install_memcached() {
    check_pkg "memcached"
    if [ $? -eq 0 ]; then
        check_pkg "python3-memcache"
        if [ $? -eq 0 ]; then
            run_cmd "systemctl enable --now memcached"
            if [ $? -eq 0 ]; then
                run_cmd "systemctl start memcached"
                if [ $? -eq 0 ]; then
                    return 0
                fi
            else
                exit 1
            fi
        else
            exit 1
        fi
    else
        return 0
    fi
}

function install_etcd() {
    check_pkg "etcd"
    if [ $? -eq 0 ]; then
        if [ ! -f /etc/default/etcd.org ]; then
            run_cmd "cp -p /etc/default/etcd /etc/default/etcd.org"
        fi

        run_cmd "cat <<EOF >/etc/default/etcd
ETCD_NAME=\"controller\"
ETCD_DATA_DIR=\"/var/lib/etcd\"
ETCD_INITIAL_CLUSTER_STATE=\"new\"
ETCD_INITIAL_CLUSTER_TOKEN=\"etcd-cluster-01\"
ETCD_INITIAL_CLUSTER=\"controller=http://${OPENSTACK_CONTROLLER_IP}:2380\"
ETCD_INITIAL_ADVERTISE_PEER_URLS=\"http://${OPENSTACK_CONTROLLER_IP}:2380\"
ETCD_ADVERTISE_CLIENT_URLS=\"http://${OPENSTACK_CONTROLLER_IP}:2379\"
ETCD_LISTEN_PEER_URLS=\"http://0.0.0.0:2380\"
ETCD_LISTEN_CLIENT_URLS=\"http://${OPENSTACK_CONTROLLER_IP}:2379\"
EOF"
        if [ $? -eq 0 ]; then
            run_cmd "systemctl enable --now etcd"
            if [ $? -eq 0 ]; then
                run_cmd "systemctl start etcd"
                if [ $? -eq 0 ]; then
                    return 0
                fi
            else
                exit 1
            fi
        else
            exit 1
        fi
    else
        return 0
    fi
}

function install_keystone() {
    check_db "keystone"
    if [ $? -eq 0 ]; then
        _CMD=(
            "CREATE DATABASE keystone;"
            "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'controller' IDENTIFIED BY '${KEYSTONE_DBPASS}';"
            "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DBPASS}';"
            # "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '${KEYSTONE_DBPASS}';"
        )
        for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
            run_cmd "mysql -uroot -p'${DB_PASS}' mysql -e \"${_CMD[${_IDX}]}\""
            if [ $? -eq 0 ]; then
                continue
            else
                exit 1
            fi
        done
    fi

    check_pkg "keystone"
    if [ $? -eq 0 ]; then
        run_cmd "systemctl stop apache2"
        if [ ! -f /etc/keystone/keystone.conf.org ]; then
            run_cmd "cp -p /etc/keystone/keystone.conf /etc/keystone/keystone.conf.org"
        fi
        _CMD=(
            "sed -i 's/^connection = sqlite/#&/g' /etc/keystone/keystone.conf"
            "sed -i'' -r -e '/^#connection = sqlit/a\connection = mysql+pymysql:\/\/keystone:''${KEYSTONE_DBPASS}''@controller\/keystone' /etc/keystone/keystone.conf"
            "sed -i 's/^\[token\]/#&\nprovider = fernet/g' /etc/keystone/keystone.conf"
        )
        for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
            run_cmd "${_CMD[${_IDX}]}"
            if [ $? -eq 0 ]; then
                continue
            else
                exit 1
            fi
        done
    fi

    if ! mysql -uroot -p''${DB_PASS}'' keystone -e "show tables;" |grep -wq 'user'; then
        run_cmd "su -s /bin/sh -c \"keystone-manage db_sync\" keystone"
        if [ $? -eq 0 ]; then
            run_cmd "keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone"
            run_cmd "keystone-manage credential_setup --keystone-user keystone --keystone-group keystone"
            run_cmd "keystone-manage bootstrap --bootstrap-password ${ADMIN_PASS} \
--bootstrap-admin-url http://controller:5000/v3/ \
--bootstrap-internal-url http://controller:5000/v3/ \
--bootstrap-public-url http://controller:5000/v3/ \
--bootstrap-region-id RegionOne"
        fi
    else
        log_msg "SKIP" "Already DB-sync keystone."
    fi

    if [ ! -f /etc/apache2/apache2.conf.org ]; then
        run_cmd "cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf.org"
        run_cmd "echo 'ServerName controller' >>/etc/apache2/apache2.conf"
    fi

    check_svc "apache2"
    if [ $? -eq 0 ]; then
        run_cmd "cat <<EOF >${SCRIPT_DIR}/adminrc
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD="${ADMIN_PASS}"
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF"
        if [ -f ${SCRIPT_DIR}/adminrc ]; then
            run_cmd "source ${SCRIPT_DIR}/adminrc"
            if ! openstack project list -f json |jq '.[0].Name' |grep -wq 'service'; then
                run_cmd "openstack project create --domain default --description \"Service Project\" service"
                if [ $? -eq 0 ]; then
                    return 0
                else
                    log_msg "ERROR" "Create faile openstack project 'service'."
                    exit 1
                fi
            fi
        else
            log_msg "ERROR" "file not found source ${SCRIPT_DIR}/adminrc"
            exit 1
        fi
    else
        return 1
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


    if [ ${SVR_MODE} == "controller" ]; then
        install_ntp
        install_openstack_client
        install_mysql
        install_mysql_python
        install_rabbitmq
        install_memcached
        install_etcd
        install_keystone

    elif [ ${SVR_MODE} == "compute" ]; then
        install_ntp
        install_openstack_client

    else
        log_msg "FAIL" "Please check option -m [ supported 'controller' or 'compute' ]."
        help_usage
        exit 1
    fi
}

main $*