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
            if [ ! -f /etc/memcached.conf.org ]; then
                run_cmd "cp -p /etc/memcached.conf /etc/memcached.conf.org"
            fi

            if ! grep -q '-l controller' /etc/memcached.conf; then
                run_cmd "sed -i 's/-l 127.0.0.1/#&\n-l controller/g' /etc/memcached.conf"
                if [ $? -eq 0 ]; then
                    enable_svc "memcached"
                    if [ $? -eq 0 ]; then
                        return 0
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

    enable_svc "apache2"
    if [ $? -eq 0 ]; then
        if [ -f ${SCRIPT_DIR}/adminrc ]; then
            # run_cmd "source ${SCRIPT_DIR}/adminrc"
            if ! openstack project list -f json |jq '.[0].Name' |grep -wq 'service'; then
                run_cmd "openstack project create --domain default --description \"Service Project\" service"
                if [ $? -eq 0 ]; then
                    return 0
                else
                    log_msg "ERROR" "Create faile openstack project 'service'."
                    exit 1
                fi
            else
                log_msg "SKIP" "Already openstack admin setting"
                return 0
            fi
        else
            log_msg "ERROR" "file not found source ${SCRIPT_DIR}/adminrc"
            exit 1
        fi
    else
        return 1
    fi
}

function install_glance() {
    check_db "glance"
    if [ $? -eq 0 ]; then
        _CMD=(
            "CREATE DATABASE glance;"
            "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'controller' IDENTIFIED BY '${GLANCE_DBPASS}';"
            "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '${GLANCE_DBPASS}';"
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

    if [ -f ${SCRIPT_DIR}/adminrc ]; then
        # run_cmd "source ${SCRIPT_DIR}/adminrc"
        ops_init "glance" "${GLANCE_PASS}" "image" "9292"
    fi

    check_pkg "glance"
    if [ $? -eq 0 ]; then
        run_cmd "systemctl stop glance-api"
        if [ ! -f /etc/glance/glance-api.conf.org ]; then
            run_cmd "cp -p /etc/glance/glance-api.conf /etc/glance/glance-api.conf.org"
        fi

        _CMD=(
            "sed -i 's/^connection = sqlite/#&/g'"
            "sed -i'' -r -e '/^#connection = sqlit/a\connection = mysql+pymysql:\/\/glance:${GLANCE_DBPASS}@controller\/glance'"
            "sed -i'' -r -e '/^\[keystone_authtoken\]/a\www_authenticate_uri = http:\/\/controller:5000\nauth_url = http:\/\/controller:5000\nmemcached_servers = controller:11211\nauth_type = password\nproject_domain_name = Default\nuser_domain_name = Default\nproject_name = service\nusername = glance\npassword = \"${GLANCE_PASS}\"'"
            "sed -i'' -r -e '/^\[paste_deploy\]/a\flavor = keystone'"
            "sed -i'' -r -e '/^\[DEFAULT\]/a\enabled_backends=fs:file'"
            "sed -i'' -r -e '/^\[glance_store\]/a\default_backend = fs'"
            "sed -ie '\$a[fs]\nfilesystem_store_datadir = \/var\/lib\/glance\/images'"
        )
        for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
            run_cmd "${_CMD[${_IDX}]} /etc/glance/glance-api.conf"
            if [ $? -eq 0 ]; then
                continue
            else
                exit 1
            fi
        done
    fi

    enable_svc "glance-api"
    if [ $? -eq 0 ]; then
        if ! mysql -uroot -p''${DB_PASS}'' glance -e "show tables;" |grep -wq 'images'; then
            run_cmd "su -s /bin/sh -c \"glance-manage db_sync\" glance"
            if [ $? -eq 0 ]; then
                run_cmd "systemctl restart glance-api"
                if [ $? -eq 0 ]; then
                    return 0
                else
                    log_msg "ERROR" "Fail service start glance."
                fi
            fi
        else
            log_msg "SKIP" "Already DB-sync glance."
        fi
    else
        exit 1
    fi

    if [ ! -f ${SCRIPT_DIR}/cirros-0.4.0-x86_64-disk.img ]; then
        run_cmd "wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img -P ${SCRIPT_DIR}"
        if [ $? -eq 1 ]; then
            log_msg "WARR" "Fail image Download cirros-0.4.0-x86_64-disk.img."
            while true; do
                read -p "Continue(Y|N)? " _ANSWER
                case ${_ANSWER} in
                    y | Y ) break  ;;
                    n | n ) exit 0 ;;
                    * ) continue   ;;
                esac
            done
        fi
    fi

    if ! openstack image show cirros -f json |jq .status |grep -wq active; then
        run_cmd "glance image-create --name 'cirros' --file cirros-0.4.0-x86_64-disk.img --disk-format qcow2 --container-format bare --visibility=public --hidden False"
        if [ $? -eq 0 ]; then
            return 0
        else
            log_msg "ERROR" "Fail upload image."
            return 1
        fi
    else
        return 0
    fi
}

function install_placement() {
    check_db "placement"
    if [ $? -eq 0 ]; then
        _CMD=(
            "CREATE DATABASE placement;"
            "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'controller' IDENTIFIED BY '${PLACEMENT_DBPASS}';"
            "GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '${PLACEMENT_DBPASS}';"
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

    if [ -f ${SCRIPT_DIR}/adminrc ]; then
        # run_cmd "source ${SCRIPT_DIR}/adminrc"
        ops_init "placement" "${PLACEMENT_PASS}" "placement" "8778"
    fi

    check_pkg "placement-api"
    if [ $? -eq 0 ]; then
        run_cmd "systemctl stop apache2"
        if [ ! -f /etc/placement/placement.conf.org ]; then
            run_cmd "cp -p /etc/placement/placement.conf /etc/placement/placement.conf.org"
        fi

        _CMD=(
            "sed -i 's/^connection = sqlite/#&/g'"
            "sed -i'' -r -e '/^#connection = sqlit/a\connection = mysql+pymysql:\/\/placement:${PLACEMENT_DBPASS}@controller\/placement'"
            "sed -i'' -r -e '/^\[api\]/a\auth_strategy = keystone'"
            "sed -i'' -r -e '/^\[keystone_authtoken\]/a\auth_url = http:\/\/controller:5000/\v3\nmemcached_servers = controller:11211\nauth_type = password\nproject_domain_name = Default\nuser_domain_name = Default\nproject_name = service\nusername = placement\npassword = \"${PLACEMENT_PASS}\"'"
        )
        for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
            run_cmd "${_CMD[${_IDX}]} /etc/placement/placement.conf"
            if [ $? -eq 0 ]; then
                continue
            else
                exit 1
            fi
        done
    fi

    run_cmd "systemctl start apache2"
    if [ $? -eq 0 ]; then
        if ! mysql -uroot -p''${DB_PASS}'' placement -e "show tables;" |grep -wq 'users'; then
            run_cmd "su -s /bin/sh -c \"placement-manage db sync\" placement"
            if [ $? -eq 0 ]; then
                run_cmd "systemctl restart apache2"
                if [ $? -eq 0 ]; then
                    return 0
                else
                    log_msg "ERROR" "Fail service start placement."
                fi
            fi
        else
            log_msg "SKIP" "Already DB-sync placement."
        fi
    else
        exit 1
    fi
}

function install_nova() {
    if [ ${SVR_MODE} == "controller" ]; then
        for _DB in nova nova_api nova_cell0; do
            check_db "${_DB}"
            if [ $? -eq 0 ]; then
                _CMD=(
                    "CREATE DATABASE ${_DB};"
                    "GRANT ALL PRIVILEGES ON ${_DB}.* TO 'nova'@'controller' IDENTIFIED BY '${NOVA_DBPASS}';"
                    "GRANT ALL PRIVILEGES ON ${_DB}.* TO 'nova'@'%' IDENTIFIED BY '${NOVA_DBPASS}';"
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
        done

        if [ -f ${SCRIPT_DIR}/adminrc ]; then
            # run_cmd "source ${SCRIPT_DIR}/adminrc"
            ops_init "nova" "${NOVA_PASS}" "compute" "8774"
        fi

        check_pkg "nova-api" "nova-conductor" "nova-novncproxy" "nova-scheduler"
        if [ $? -eq 0 ]; then
            run_cmd "systemctl stop nova-api nova-conductor nova-novncproxy nova-scheduler"
            if [ ! -f /etc/nova/nova.conf.org ]; then
                run_cmd "cp -p /etc/nova/nova.conf /etc/nova/nova.conf.org"
            fi
            _CMD=(
                "sed -i 's/^connection = sqlite/#&/g'"
                "sed -i'' -r -e '/^\[api_database\]/a\connection = mysql+pymysql:\/\/nova:${NOVA_DBPASS}@controller\/nova_api'"
                "sed -i'' -r -e '/^\[database\]/a\connection = mysql+pymysql:\/\/nova:${NOVA_DBPASS}@controller\/nova'"
                "sed -i'' -r -e '/^\[DEFAULT\]/a\transport_url = rabbit:\/\/openstack:${RABBIT_PASS}@controller:5672\nmy_ip = ${OPENSTACK_CONTROLLER_IP}'"
                "sed -i'' -r -e '/^\[api\]/a\auth_strategy = keystone'"
                "sed -i'' -r -e '/^\[keystone_authtoken\]/a\www_authenticate_uri = http:\/\/controller:5000\nauth_url = http:\/\/controller:5000\nmemcached_servers = controller:11211\nauth_type = password\nproject_domain_name = Default\nuser_domain_name = Default\nproject_name = service\nusername = nova\npassword = \"${NOVA_PASS}\"'"
                "sed -i'' -r -e '/^\[vnc\]/a\enabled = true\nserver_listen = \$my_ip\nserver_proxyclient_address = \$my_ip'"
                "sed -i'' -r -e '/^\[glance\]/a\api_servers = http:\/\/controller:9292'"
                "sed -i'' -r -e '/^\[oslo_concurrency\]/a\lock_path = \/var\/lib\/nova\/tmp'"
                "sed -i'' -r -e '/^\[placement\]/a\region_name = RegionOne\nproject_domain_name = Default\nproject_name = service\nauth_type = password\nuser_domain_name = Default\nauth_url = http:\/\/controller:5000\/v3\nusername = placement\npassword = \"${PLACEMENT_PASS}\"'"
            )
            for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
                run_cmd "${_CMD[${_IDX}]} /etc/nova/nova.conf"
                if [ $? -eq 0 ]; then
                    continue
                else
                    exit 1
                fi
            done
        fi

        enable_svc "nova-api" "nova-conductor" "nova-novncproxy" "nova-scheduler"
        if [ $? -eq 0 ]; then
            if ! mysql -uroot -p''${DB_PASS}'' nova_api -e "show tables;" |grep -wq 'key_pairs'; then
                run_cmd "su -s /bin/sh -c \"nova-manage api_db sync\" nova"
                if [ $? -eq 1 ]; then
                    exit 1
                fi
            else
                log_msg "SKIP" "Already DB-sync nova_api."
            fi

            if ! nova-manage cell_v2 list_cells |grep -wq 'cell0'; then
                run_cmd "su -s /bin/sh -c \"nova-manage cell_v2 map_cell0\" nova"
                if [ $? -eq 1 ]; then
                    exit 1
                fi
            else
                log_msg "SKIP" "Already mapping cell0."
            fi

            if ! nova-manage cell_v2 list_cells |grep -wq 'cell1'; then
                run_cmd "su -s /bin/sh -c \"nova-manage cell_v2 create_cell --name=cell1 --verbose\" nova"
                if [ $? -eq 1 ]; then
                    exit 1
                fi
            else
                log_msg "SKIP" "Already mapping cell1."
            fi
            
            if ! mysql -uroot -p''${DB_PASS}'' nova -e "show tables;" |grep -wq 'fixed_ips'; then
                run_cmd "su -s /bin/sh -c \"nova-manage db sync\" nova"
                if [ $? -eq 0 ]; then
                    run_cmd "systemctl restart nova-api nova-conductor nova-novncproxy nova-scheduler"
                    if [ $? -eq 0 ]; then
                        return 0
                    else
                        log_msg "ERROR" "Fail service start nova."
                    fi
                fi
            else
                log_msg "SKIP" "Already DB-sync nova."
            fi
        else
            exit 1
        fi

    #####################################################################
    elif [ ${SVR_MODE} == "compute" ]; then
        check_pkg "nova-compute"
    
        if [ $? -eq 0 ]; then
            run_cmd "systemctl stop nova-compute"
            if [ ! -f /etc/nova/nova.conf.org ]; then
                run_cmd "cp -p /etc/nova/nova.conf /etc/nova/nova.conf.org"
            fi

            _CMD=(
                "sed -i'' -r -e '/^\[DEFAULT\]/a\transport_url = rabbit:\/\/openstack:${RABBIT_PASS}@controller:5672\nmy_ip = ${OPENSTACK_COMPUTE_IP}'"
                "sed -i'' -r -e '/^\[api\]/a\auth_strategy = keystone'"
                "sed -i'' -r -e '/^\[keystone_authtoken\]/a\www_authenticate_uri = http:\/\/controller:5000\nauth_url = http:\/\/controller:5000\nmemcached_servers = controller:11211\nauth_type = password\nproject_domain_name = Default\nuser_domain_name = Default\nproject_name = service\nusername = nova\npassword = \"${NOVA_PASS}\"'"
                "sed -i'' -r -e '/^\[vnc\]/a\enabled = true\nserver_listen = 0.0.0.0\nserver_proxyclient_address = \$my_ip\nnovncproxy_base_url = http:\/\/controller:6080/vnc_auto.html'"
                "sed -i'' -r -e '/^\[glance\]/a\api_servers = http:\/\/controller:9292'"
                "sed -i'' -r -e '/^\[oslo_concurrency\]/a\lock_path = \/var\/lib\/nova\/tmp'"
                "sed -i'' -r -e '/^\[placement\]/a\region_name = RegionOne\nproject_domain_name = Default\nproject_name = service\nauth_type = password\nuser_domain_name = Default\nauth_url = http:\/\/controller:5000\/v3\nusername = placement\npassword = \"${PLACEMENT_PASS}\"'"
            )
            for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
                run_cmd "${_CMD[${_IDX}]} /etc/nova/nova.conf"
                if [ $? -eq 0 ]; then
                    continue
                else
                    exit 1
                fi
            done

            enable_svc "nova-compute"
            if [ $? -eq 0 ]; then
                return 0
            else
                exit 1
            fi
        fi
    fi
}


# 동백수목원, 동박낭
function install_neutron() {
    if [ ${SVR_MODE} == "controller" ]; then
        check_db "neutron"
        if [ $? -eq 0 ]; then
            _CMD=(
                "CREATE DATABASE neutron;"
                "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'controller' IDENTIFIED BY '${NEUTRON_DBPASS}';"
                "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '${NEUTRON_DBPASS}';"
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

        if [ -f ${SCRIPT_DIR}/adminrc ]; then
            # run_cmd "source ${SCRIPT_DIR}/adminrc"
            ops_init "neutron" "${NEUTRON_PASS}" "network" "9696"
        fi

        check_pkg "neutron-server" "neutron-plugin-ml2" "neutron-openvswitch-agent" "neutron-l3-agent" "neutron-dhcp-agent" "neutron-metadata-agent"
        if [ $? -eq 0 ]; then
            # run_cmd "systemctl stop neutron-server neutron-openvswitch-agent neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent"
            _FILE=(
                "/etc/neutron/neutron.conf"
                "/etc/neutron/plugins/ml2/ml2_conf.ini"
                "/etc/neutron/plugins/ml2/openvswitch_agent.ini"
                "/etc/neutron/l3_agent.ini"
                "/etc/neutron/dhcp_agent.ini"
                "/etc/neutron/metadata_agent.ini"
            )
            for ((_IDX=0 ; _IDX < ${#_FILE[@]} ; _IDX++)); do
                # run_cmd "cp -p ${_FILE[${_IDX}]}.org ${_FILE[${_IDX}]}"
                if [ ! -f ${_FILE[${_IDX}]}.org ]; then
                    run_cmd "cp -p ${_FILE[${_IDX}]} ${_FILE[${_IDX}]}.org"
                    if [ $? -eq 0 ]; then
                        continue
                    else
                        exit 1
                    fi
                fi
            done
        fi

        if ! ovs-vsctl list-br |grep -wq ${PROVIDER_BRIDGE_NAME} >/dev/null 2>&1; then
            run_cmd "ovs-vsctl add-br ${PROVIDER_BRIDGE_NAME}"
            if [ $? -eq 1 ]; then
                exit 1
            fi
        else
            log_msg "SKIP" "Already ovs bridge ${PROVIDER_BRIDGE_NAME}."
        fi

        if ! ovs-vsctl list-ports ${PROVIDER_BRIDGE_NAME} |grep -wq ${PROVIDER_INTERFACE} >/dev/null 2>&1; then 
            ovs-vsctl add-port ${PROVIDER_BRIDGE_NAME} ${PROVIDER_INTERFACE}
            echo "$?" ; exit 0
            if [ $? -eq 1 ]; then
                exit 1
            fi
        else
            log_msg "SKIP" "Already ovs bridge to add ${PROVIDER_INTERFACE}."
        fi

        _SETUP_NEUTRON_CNT=0
        #### Neutron config
        _CMD=(
            "sed -i 's/^connection = sqlite/#&/g'"
            "sed -i'' -r -e '/^\[database\]/a\connection = mysql+pymysql:\/\/neutron:${NEUTRON_DBPASS}@controller\/neutron'"
            "sed -i'' -r -e '/^\[DEFAULT\]/a\core_plugin = ml2\nservice_plugins = router\ntransport_url = rabbit:\/\/openstack:${RABBIT_PASS}@controller\nauth_strategy = keystone\nnotify_nova_on_port_status_changes = true\nnotify_nova_on_port_data_changes = true'"
            "sed -i'' -r -e '/^\[keystone_authtoken\]/a\www_authenticate_uri = http:\/\/controller:5000\nauth_url = http:\/\/controller:5000\nmemcached_servers = controller:11211\nauth_type = password\nproject_domain_name = Default\nuser_domain_name = Default\nproject_name = service\nusername = neutron\npassword = \"${NEUTRON_PASS}\"'"
            "sed -i'' -r -e '/^\[nova\]/a\auth_url = http:\/\/controller:5000\nauth_type = password\nproject_domain_name = Default\nuser_domain_name = Default\nregion_name = RegionOne\nproject_name = service\nusername = nova\npassword = \"${NEUTRON_PASS}\"'"
            "sed -i'' -r -e '/^\[oslo_concurrency\]/a\lock_path = \/var\/lib\/neutron\/tmp'"
        )
        if ! grep -Fq "password = \"${NEUTRON_PASS}\"" /etc/neutron/neutron.conf; then
            for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
                run_cmd "${_CMD[${_IDX}]} /etc/neutron/neutron.conf"
                if [ $? -eq 0 ]; then
                    _SETUP_NEUTRON_CNT=$(expr ${_SETUP_NEUTRON_CNT} + 1)
                    continue
                else
                    exit 1
                fi
            done
        else
            log_msg "SKIP" "Already setting /etc/neutron/neutron.conf"
        fi

        #### Neutron ml2 config
        _CMD=(
            "sed -i'' -r -e '/^\[ml2\]/a\type_drivers = flat,vlan,vxlan\ntenant_network_types = vxlan\nmechanism_drivers = openvswitch,l2population\nextension_drivers = port_security'"
            "sed -i'' -r -e '/^\[ml2_type_flat\]/a\flat_networks = provider'"
            "sed -i'' -r -e '/^\[ml2_type_vxlan\]/a\vni_ranges = ${VNI_START}:${VNI_END}'"
        )
        if ! grep -q "flat_networks = provider" /etc/neutron/plugins/ml2/ml2_conf.ini; then 
            for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
                run_cmd "${_CMD[${_IDX}]} /etc/neutron/plugins/ml2/ml2_conf.ini"
                if [ $? -eq 0 ]; then
                    _SETUP_NEUTRON_CNT=$(expr ${_SETUP_NEUTRON_CNT} + 1)
                    continue
                else
                    exit 1
                fi
            done
        else
            log_msg "SKIP" "Already setting /etc/neutron/plugins/ml2/ml2_conf.ini"
        fi

        #### Neutron openvswitch config
        _CMD=(
            "sed -i'' -r -e '/^\[ovs\]/a\bridge_mappings = provider:${PROVIDER_BRIDGE_NAME}\nlocal_ip = ${OVERLAY_INTERFACE_CONTROLLER_IP_ADDRESS}'"
            "sed -i'' -r -e '/^\[agent\]/a\tunnel_types = vxlan\nl2_population = true'"
            "sed -i'' -r -e '/^\[securitygroup\]/a\enable_security_group = true\nfirewall_driver = openvswitch'"
        )
        if ! grep -q "local_ip = ${OVERLAY_INTERFACE_CONTROLLER_IP_ADDRESS}" /etc/neutron/plugins/ml2/openvswitch_agent.ini; then 
            for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
                run_cmd "${_CMD[${_IDX}]} /etc/neutron/plugins/ml2/openvswitch_agent.ini"
                if [ $? -eq 0 ]; then
                    _SETUP_NEUTRON_CNT=$(expr ${_SETUP_NEUTRON_CNT} + 1)
                    continue
                else
                    exit 1
                fi        
            done
        else
            log_msg "SKIP" "Already setting /etc/neutron/plugins/ml2/openvswitch_agent.ini"
        fi
        
        #### Neutron l3 config
        _CMD=(
            "sed -i'' -r -e '/^\[DEFAULT\]/a\interface_driver = openvswitch'"
        )
        if ! grep -q "interface_driver = openvswitch" /etc/neutron/l3_agent.ini; then 
            for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
                run_cmd "${_CMD[${_IDX}]} /etc/neutron/l3_agent.ini"
                if [ $? -eq 0 ]; then
                    _SETUP_NEUTRON_CNT=$(expr ${_SETUP_NEUTRON_CNT} + 1)
                    continue
                else
                    exit 1
                fi
            done
        else
            log_msg "SKIP" "Already setting /etc/neutron/l3_agent.ini"
        fi

        #### Neutron dhcp config
        _CMD=(
            "sed -i'' -r -e '/^\[DEFAULT\]/a\interface_driver = openvswitch\ndhcp_driver = neutron.agent.linux.dhcp.Dnsmasq\nenable_isolated_metadata = true'"
        )
        if ! grep -q "interface_driver = openvswitch" /etc/neutron/dhcp_agent.ini; then
            for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
                run_cmd "${_CMD[${_IDX}]} /etc/neutron/dhcp_agent.ini"
                if [ $? -eq 0 ]; then
                    _SETUP_NEUTRON_CNT=$(expr ${_SETUP_NEUTRON_CNT} + 1)
                    continue
                else
                    exit 1
                fi

            done
        else
            log_msg "SKIP" "Already setting /etc/neutron/dhcp_agent.ini"
        fi

        #### Neutron metadata config
        _CMD=(
            "sed -i'' -r -e '/^\[DEFAULT\]/a\nova_metadata_host = controller\nmetadata_proxy_shared_secret = \"${METADATA_SECRET}\"'"
        )
        if ! grep -Fq "metadata_proxy_shared_secret = \"${METADATA_SECRET}\"" /etc/neutron/metadata_agent.ini; then
            for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
                run_cmd "${_CMD[${_IDX}]} /etc/neutron/metadata_agent.ini"
                if [ $? -eq 0 ]; then
                    _SETUP_NEUTRON_CNT=$(expr ${_SETUP_NEUTRON_CNT} + 1)
                    continue
                else
                    exit 1
                fi
            done
        else
            log_msg "SKIP" "Already setting /etc/neutron/metadata_agent.ini"
        fi

        #### Neutron nova config
        _CMD=(
            "sed -i'' -r -e '/^\[neutron\]/a\auth_url = http:\/\/controller:5000\nauth_type = password\nproject_domain_name = Default\nuser_domain_name = Default\nregion_name = RegionOne\nproject_name = service\nusername = neutron\npassword = \"${NEUTRON_PASS}\"\nservice_metadata_proxy = true\nmetadata_proxy_shared_secret = \"${METADATA_SECRET}\"'"
        )
        if ! grep -Fq "password = \"${NEUTRON_PASS}\"" /etc/nova/nova.conf; then
            for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
                run_cmd "${_CMD[${_IDX}]} /etc/nova/nova.conf"
                if [ $? -eq 0 ]; then
                    _SETUP_NEUTRON_CNT=$(expr ${_SETUP_NEUTRON_CNT} + 1)
                    continue
                else
                    exit 1
                fi
            done
        else
            log_msg "SKIP" "Already setting /etc/nova/nova.conf"
        fi

        run_cmd "systemctl restart nova-api"
        if [ $? -eq 0 ]; then
            if ! mysql -uroot -p''${DB_PASS}'' neutron -e "show tables;" |grep -wq 'vips'; then
                run_cmd "su -s /bin/sh -c \"neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head\" neutron"
                if [ $? -eq 0 ]; then
                    enable_svc "neutron-server" "neutron-openvswitch-agent" "neutron-dhcp-agent" "neutron-metadata-agent" "neutron-l3-agent"
                    if [ $? -eq 0 ]; then
                        return 0
                    else
                        exit 1
                    fi
                else
                    exit 1
                fi
            else
                log_msg "SKIP" "Already DB-sync neutron."
            fi
        else
            exit 1
        fi

    #####################################################################
    elif [ ${SVR_MODE} == "compute" ]; then
        check_pkg "neutron-openvswitch-agent"
        if [ $? -eq 0 ]; then
            # run_cmd "systemctl stop neutron-server neutron-openvswitch-agent neutron-dhcp-agent neutron-metadata-agent neutron-l3-agent"
            _FILE=(
                "/etc/neutron/neutron.conf"
                "/etc/neutron/plugins/ml2/openvswitch_agent.ini"
            )
            for ((_IDX=0 ; _IDX < ${#_FILE[@]} ; _IDX++)); do
                if [ ! -f ${_FILE[${_IDX}]}.org ]; then
                    run_cmd "cp -p ${_FILE[${_IDX}]} ${_FILE[${_IDX}]}.org"
                    if [ $? -eq 0 ]; then
                        continue
                    else
                        exit 1
                    fi
                fi
            done
        fi

        if ! ovs-vsctl list-br |grep -wq ${PROVIDER_BRIDGE_NAME} >/dev/null 2>&1; then
            run_cmd "ovs-vsctl add-br ${PROVIDER_BRIDGE_NAME}"
            if [ $? -eq 1 ]; then
                exit 1
            fi
        else
            log_msg "SKIP" "Already ovs bridge ${PROVIDER_BRIDGE_NAME}."
        fi

        if ! ovs-vsctl list-ports ${PROVIDER_BRIDGE_NAME} |grep -wq ${PROVIDER_INTERFACE} >/dev/null 2>&1; then 
            ovs-vsctl add-port ${PROVIDER_BRIDGE_NAME} ${PROVIDER_INTERFACE}
            echo "$?" ; exit 0
            if [ $? -eq 1 ]; then
                exit 1
            fi
        else
            log_msg "SKIP" "Already ovs bridge to add ${PROVIDER_INTERFACE}."
        fi

        _SETUP_NEUTRON_CNT=0
        #### Neutron config
        _CMD=(
            "sed -i'' -r -e '/^\[DEFAULT\]/a\transport_url = rabbit:\/\/openstack:${RABBIT_PASS}@controller'"
            "sed -i'' -r -e '/^\[oslo_concurrency\]/a\lock_path = \/var\/lib\/neutron\/tmp'"
        )
        if ! grep -Fq "openstack:${RABBIT_PASS}" /etc/neutron/neutron.conf; then
            for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
                run_cmd "${_CMD[${_IDX}]} /etc/neutron/neutron.conf"
                if [ $? -eq 0 ]; then
                    _SETUP_NEUTRON_CNT=$(expr ${_SETUP_NEUTRON_CNT} + 1)
                    continue
                else
                    exit 1
                fi
            done
        else
            log_msg "SKIP" "Already setting /etc/neutron/neutron.conf"
        fi

        #### Neutron openvswitch config
        _CMD=(
            "sed -i'' -r -e '/^\[ovs\]/a\bridge_mappings = provider:${PROVIDER_BRIDGE_NAME}\nlocal_ip = ${OVERLAY_INTERFACE_COMPUTE_IP_ADDRESS}'"
            "sed -i'' -r -e '/^\[agent\]/a\tunnel_types = vxlan\nl2_population = true'"
            # "sed -i'' -r -e '/^\[securitygroup\]/a\enable_security_group = true\nfirewall_driver = openvswitch'"
            "sed -i'' -r -e '/^\[securitygroup\]/a\enable_security_group = true\nfirewall_driver = iptables_hybrid'"
        )
        if ! grep -q "local_ip = ${OVERLAY_INTERFACE_COMPUTE_IP_ADDRESS}" /etc/neutron/plugins/ml2/openvswitch_agent.ini; then 
            for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
                run_cmd "${_CMD[${_IDX}]} /etc/neutron/plugins/ml2/openvswitch_agent.ini"
                if [ $? -eq 0 ]; then
                    _SETUP_NEUTRON_CNT=$(expr ${_SETUP_NEUTRON_CNT} + 1)
                    continue
                else
                    exit 1
                fi        
            done
        else
            log_msg "SKIP" "Already setting /etc/neutron/plugins/ml2/openvswitch_agent.ini"
        fi

        #### Neutron nova config
        _CMD=(
            "sed -i'' -r -e '/^\[neutron\]/a\auth_url = http:\/\/controller:5000\nauth_type = password\nproject_domain_name = Default\nuser_domain_name = Default\nregion_name = RegionOne\nproject_name = service\nusername = neutron\npassword = \"${NEUTRON_PASS}\"\nservice_metadata_proxy = true\nmetadata_proxy_shared_secret = \"${METADATA_SECRET}\"'"
        )
        if ! grep -Fq "password = \"${NEUTRON_PASS}\"" /etc/nova/nova.conf; then
            for ((_IDX=0 ; _IDX < ${#_CMD[@]} ; _IDX++)); do
                run_cmd "${_CMD[${_IDX}]} /etc/nova/nova.conf"
                if [ $? -eq 0 ]; then
                    _SETUP_NEUTRON_CNT=$(expr ${_SETUP_NEUTRON_CNT} + 1)
                    continue
                else
                    exit 1
                fi
            done
        else
            log_msg "SKIP" "Already setting /etc/nova/nova.conf"
        fi

        run_cmd "systemctl restart nova-compute"
        if [ $? -eq 0 ]; then
            enable_svc "neutron-openvswitch-agent"
            if [ $? -eq 0 ]; then
                return 0
            else
                exit 1
            fi
        else
            exit 1
        fi
    fi
}

function install_horizon() {
    check_pkg "openstack-dashboard"
    if [ $? -eq 0 ]; then
        if [ ! -f /etc/openstack-dashboard/local_settings.py.org ]; then
            run_cmd "cp -p /etc/openstack-dashboard/local_settings.py /etc/openstack-dashboard/local_settings.py.org"
        fi

        if ! grep -q 'OPENSTACK_HOST = "controller"' /etc/openstack-dashboard/local_settings.py; then
            run_cmd "sed -i 's/^OPENSTACK_HOST = /#&/g' /etc/openstack-dashboard/local_settings.py"
            run_cmd "sed -i'' -r -e '/^#OPENSTACK_HOST = /a\OPENSTACK_HOST = \"controller\"' /etc/openstack-dashboard/local_settings.py"
        fi

        if ! grep -q 'django.contrib.sessions.backends.cache' /etc/openstack-dashboard/local_settings.py; then
            run_cmd "sed -i'' -r -e '/^#SESSION_ENGINE/a\SESSION_ENGINE = 'django.contrib.sessions.backends.cache''"
        fi

        if ! grep -q "#'BACKEND': 'django.core.cache.backends.memcached.PyMemcacheCache'" /etc/openstack-dashboard/local_settings.py; then
            run_cmd "sed -i 's/'\''BACKEND'\''/#&/g' /etc/openstack-dashboard/local_settings.py"
            run_cmd "sed -i'' -r -e '/#'\''BACKEND'\''/a\        '\''BACKEND'\'': '\''django.core.cache.backends.memcached.MemcachedCache'\'',' /etc/openstack-dashboard/local_settings.py"
        fi

        if ! grep -q "#'LOCATION'" /etc/openstack-dashboard/local_settings.py; then
            run_cmd "sed -i 's/'\''LOCATION'\''/#&/g' /etc/openstack-dashboard/local_settings.py"
            run_cmd "sed -i'' -r -e '/#'\''LOCATION'\''/a\        '\''LOCALTION'\'': '\''controller:11211'\''' /etc/openstack-dashboard/local_settings.py"
        fi

        if ! grep -q 'Asia/Seoul' /etc/openstack-dashboard/local_settings.py; then
            run_cmd "sed -i 's/TIME_ZONE = \"UTC\"/#&\nTIME_ZONE = \"Asia\/Seoul\"/g' /etc/openstack-dashboard/local_settings.py"
        fi

        if ! grep -q 'OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT' /etc/openstack-dashboard/local_settings.py; then
            run_cmd "cat <<EOF >>/etc/openstack-dashboard/local_settings.py

OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True
OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = \"Default\"
OPENSTACK_KEYSTONE_DEFAULT_ROLE = \"user\"
EOF"
        fi

        if ! grep -q 'OPENSTACK_API_VERSIONS' /etc/openstack-dashboard/local_settings.py; then
            run_cmd "cat <<EOF >>/etc/openstack-dashboard/local_settings.py

OPENSTACK_API_VERSIONS = {
    \"identity\": 3,
    \"image\": 2,
    \"volume\": 3,
}
EOF"
        fi

        if ! grep -q 'OPENSTACK_NEUTRON_NETWORK' /etc/openstack-dashboard/local_settings.py; then
run_cmd "cat <<EOF >>/etc/openstack-dashboard/local_settings.py
 
OPENSTACK_NEUTRON_NETWORK = {
    'enable_router': False,
    'enable_quotas': False,
    'enable_ipv6': False,
    'enable_distributed_router': False,
    'enable_ha_router': False,
    'enable_fip_topology_check': False,
}
EOF"
        fi

        run_cmd "systemctl restart apache2"
        if [ $? -eq 0 ]; then
            return 0
        else
            exit 1
        fi

    else
        exit 1
    fi
}

function remove_openstack() {
    if [ ${SVR_MODE} == "controller" ]; then

        ### Neutron 서비스 종료
        disable_svc "neutron-openvswitch-agent" "neutron-dhcp-agent" "neutron-l3-agent" "neutron-server" "neutron-ovs-cleanup" "neutron-metadata-agent"
        if [ $? -eq 0 ]; then
            remove_pkg "neutron-openvswitch-agent" "neutron-dhcp-agent" "neutron-l3-agent" "neutron-server" "neutron-metadata-agent" "python3-neutronclient"
            if [ $? -eq 1 ]; then
                exit 1
            else
                _CMD=(
                    "/etc/pycadf/neutron_api_audit_map.conf"
                    "/etc/logrotate.d/neutron-common"
                    "/etc/systemd/system/neutron-dhcp-agent.service"
                    "/etc/systemd/system/neutron-openvswitch-agent.service"
                    "/etc/systemd/system/neutron-metadata-agent.service"
                    "/etc/systemd/system/neutron-l3-agent.service"
                    "/etc/systemd/system/neutron-server.service"
                    "/etc/systemd/system/neutron-ovs-cleanup.service"
                    "/etc/neutron"
                    "/etc/sudoers.d/neutron_sudoers"
                    "/etc/init.d/neutron-l3-agent"
                    "/etc/init.d/neutron-dhcp-agent"
                    "/etc/init.d/neutron-server"
                    "/etc/init.d/neutron-openvswitch-agent"
                    "/etc/init.d/neutron-ovs-cleanup"
                    "/etc/init.d/neutron-metadata-agent"
                    "/etc/default/neutron-server"
                    "/var/lib/systemd/deb-systemd-helper-masked/neutron-dhcp-agent.service"
                    "/var/lib/systemd/deb-systemd-helper-masked/neutron-openvswitch-agent.service"
                    "/var/lib/systemd/deb-systemd-helper-masked/neutron-metadata-agent.service"
                    "/var/lib/systemd/deb-systemd-helper-masked/neutron-l3-agent.service"
                    "/var/lib/systemd/deb-systemd-helper-masked/neutron-server.service"
                    "/var/lib/systemd/deb-systemd-helper-masked/neutron-ovs-cleanup.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/neutron-dhcp-agent.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/neutron-openvswitch-agent.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/neutron-metadata-agent.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/neutron-l3-agent.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/neutron-server.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/neutron-ovs-cleanup.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/neutron-openvswitch-agent.service.dsh-also"
                    "/var/lib/systemd/deb-systemd-helper-enabled/neutron-ovs-cleanup.service.dsh-also"
                    "/var/lib/systemd/deb-systemd-helper-enabled/neutron-dhcp-agent.service.dsh-also"
                    "/var/lib/systemd/deb-systemd-helper-enabled/neutron-server.service.dsh-also"
                    "/var/lib/systemd/deb-systemd-helper-enabled/neutron-metadata-agent.service.dsh-also"
                    "/var/lib/systemd/deb-systemd-helper-enabled/neutron-l3-agent.service.dsh-also"
                    "/var/lib/neutron"
                    "/var/cache/neutron"
                    "/var/log/neutron"
                )
                for _PATH in ${_CMD[@]}; do
                    if [[ -d ${_PATH} ]] || [[ -f ${_PATH} ]]; then
                        run_cmd "rm -rf ${_PATH}"
                    fi
                done
            fi
        else
            exit 1
        fi

        ### Nova 서비스 종료
        disable_svc "nova-conductor" "nova-api" "nova-scheduler" "nova-novncproxy"
        if [ $? -eq 0 ]; then
            remove_pkg "nova-conductor" "nova-api" "nova-scheduler" "nova-novncproxy" "python3-novaclient"
            if [ $? -eq 1 ]; then
                exit 1
            else
                _CMD=(
                    "/etc/rc2.d/K01nova-api"
                    "/etc/rc2.d/K01nova-conductor"
                    "/etc/rc2.d/K01nova-scheduler"
                    "/etc/rc5.d/K01nova-api"
                    "/etc/rc5.d/K01nova-conductor"
                    "/etc/rc5.d/K01nova-scheduler"
                    "/etc/pycadf/nova_api_audit_map.conf"
                    "/etc/logrotate.d/nova-common"
                    "/etc/systemd/system/nova-conductor.service"
                    "/etc/systemd/system/nova-scheduler.service"
                    "/etc/systemd/system/nova-api.service"
                    "/etc/rc3.d/K01nova-api"
                    "/etc/rc3.d/K01nova-conductor"
                    "/etc/rc3.d/K01nova-scheduler"
                    "/etc/rc1.d/K01nova-api"
                    "/etc/rc1.d/K01nova-conductor"
                    "/etc/rc1.d/K01nova-scheduler"
                    "/etc/rc4.d/K01nova-api"
                    "/etc/rc4.d/K01nova-conductor"
                    "/etc/rc4.d/K01nova-scheduler"
                    "/etc/sudoers.d/nova_sudoers"
                    "/etc/rc0.d/K01nova-api"
                    "/etc/rc0.d/K01nova-conductor"
                    "/etc/rc0.d/K01nova-scheduler"
                    "/etc/nova"
                    "/etc/init.d/nova-scheduler"
                    "/etc/init.d/nova-api"
                    "/etc/init.d/nova-conductor"
                    "/etc/rc6.d/K01nova-api"
                    "/etc/rc6.d/K01nova-conductor"
                    "/etc/rc6.d/K01nova-scheduler"
                    "/var/lib/systemd/deb-systemd-helper-masked/nova-conductor.service"
                    "/var/lib/systemd/deb-systemd-helper-masked/nova-scheduler.service"
                    "/var/lib/systemd/deb-systemd-helper-masked/nova-api.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/nova-conductor.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/nova-scheduler.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/nova-api.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/nova-scheduler.service.dsh-also"
                    "/var/lib/systemd/deb-systemd-helper-enabled/nova-api.service.dsh-also"
                    "/var/lib/systemd/deb-systemd-helper-enabled/nova-conductor.service.dsh-also"
                    "/var/lib/nova"
                    "/var/lib/dpkg/info/nova-api.postrm"
                    "/var/lib/dpkg/info/nova-scheduler.postrm"
                    "/var/lib/dpkg/info/nova-conductor.postrm"
                    "/var/lib/dpkg/info/nova-conductor.list"
                    "/var/lib/dpkg/info/nova-scheduler.list"
                    "/var/lib/dpkg/info/nova-api.list"
                    "/var/lib/dpkg/info/nova-common.list"
                    "/var/cache/apt/archives/nova-common_3%3a25.2.1-0ubuntu2.3_all.deb"
                    "/var/cache/apt/archives/python3-nova_3%3a25.2.1-0ubuntu2.3_all.deb"
                    "/var/cache/apt/archives/nova-novncproxy_3%3a25.2.1-0ubuntu2.3_all.deb"
                    "/var/cache/apt/archives/nova-api_3%3a25.2.1-0ubuntu2.3_all.deb"
                    "/var/cache/apt/archives/nova-scheduler_3%3a25.2.1-0ubuntu2.3_all.deb"
                    "/var/cache/apt/archives/nova-conductor_3%3a25.2.1-0ubuntu2.3_all.deb"
                    "/var/cache/nova"
                    "/var/log/nova"
                )
                for _PATH in ${_CMD[@]}; do
                    if [[ -d ${_PATH} ]] || [[ -f ${_PATH} ]]; then
                        run_cmd "rm -rf ${_PATH}"
                    fi
                done
            fi
        else
            exit 1
        fi

        ### Glance 서비스 종료
        disable_svc "glance-api"
        if [ $? -eq 0 ]; then
            remove_pkg "glance" "python3-glance-client"
            if [ $? -eq 1 ]; then
                exit 1
            else
                _CMD=(
                    "/etc/rc2.d/K01glance-api"
                    "/etc/rc5.d/K01glance-api"
                    "/etc/pycadf/glance_api_audit_map.conf"
                    "/etc/glance"
                    "/etc/logrotate.d/glance-common"
                    "/etc/systemd/system/glance-api.service"
                    "/etc/rc3.d/K01glance-api"
                    "/etc/rc1.d/K01glance-api"
                    "/etc/rc4.d/K01glance-api"
                    "/etc/sudoers.d/glance_sudoers"
                    "/etc/rc0.d/K01glance-api"
                    "/etc/init.d/glance-api"
                    "/etc/rc6.d/K01glance-api"
                    "/var/lib/glance"
                    "/var/lib/systemd/deb-systemd-helper-masked/glance-api.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/glance-api.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/glance-api.service.dsh-also"
                    "/var/lib/dpkg/info/python3-glance-store.list"
                    "/var/lib/dpkg/info/glance-common.list"
                    "/var/lib/dpkg/info/glance-api.postrm"
                    "/var/lib/dpkg/info/glance-api.list"
                    "/var/lib/dpkg/info/glance-common.postrm"
                    "/var/cache/apt/archives/python3-glance-store_4.7.0-0ubuntu1~cloud0_all.deb"
                    "/var/cache/apt/archives/glance-common_2%3a28.0.1-0ubuntu1.2~cloud0_all.deb"
                    "/var/cache/apt/archives/glance-api_2%3a28.0.1-0ubuntu1.2~cloud0_all.deb"
                    "/var/cache/apt/archives/python3-glance_2%3a28.0.1-0ubuntu1.2~cloud0_all.deb"
                    "/var/cache/apt/archives/glance_2%3a28.0.1-0ubuntu1.2~cloud0_all.deb"
                    "/var/cache/apt/archives/python3-glanceclient_1%3a4.4.0-0ubuntu1~cloud0_all.deb"
                    "/var/cache/glance"
                    "/var/log/glance"
                )
                for _PATH in ${_CMD[@]}; do
                    if [[ -d ${_PATH} ]] || [[ -f ${_PATH} ]]; then
                        run_cmd "rm -rf ${_PATH}"
                    fi
                done
            fi
        else
            exit 1
        fi

        ### Keystoen, Placement, Horizon 서비스 종료
        disable_svc "apache2"
        if [ $? -eq 0 ]; then
            remove_pkg "placement-api" "keystone" "python3-openstackclient" "python3-keystoneauth1" "python3-keystoneclient"
            if [ $? -eq 1 ]; then
                exit 1
            else
                _CMD=(
                    "/etc/logrotate.d/placement-common"
                    "/etc/placement"
                    "/var/lib/placement"
                    "/var/lib/dpkg/info/placement-common.list"
                    "/var/lib/dpkg/info/placement-api.list"
                    "/var/lib/dpkg/info/placement-api.postrm"
                    "/etc/logrotate.d/keystone-common"
                    "/etc/keystone"
                    "/var/lib/keystone"
                    "/var/lib/dpkg/info/keystone.list"
                    "/var/lib/dpkg/info/keystone.postrm"
                    "/var/lib/dpkg/info/keystone-common.list"
                    "/var/lib/dpkg/info/keystone-common.postrm"
                    "/var/cache/apt/archives/keystone_2%3a25.0.0-0ubuntu1~cloud0_all.deb"
                    "/var/cache/apt/archives/keystone-common_2%3a25.0.0-0ubuntu1~cloud0_all.deb"
                    "/var/cache/apt/archives/python3-keystone_2%3a25.0.0-0ubuntu1~cloud0_all.deb"
                    "/var/cache/apt/archives/python3-keystonemiddleware_10.6.0-0ubuntu1~cloud0_all.deb"
                    "/var/cache/apt/archives/python3-keystoneauth1_5.6.0-0ubuntu1~cloud0_all.deb"
                    "/var/log/keystone"
                    "/etc/rc2.d/S01apache2"
                    "/etc/rc2.d/K01apache-htcacheclean"
                    "/etc/rc5.d/S01apache2"
                    "/etc/rc5.d/K01apache-htcacheclean"
                    "/etc/apache2"
                    "/etc/logrotate.d/apache2"
                    "/etc/systemd/system/multi-user.target.wants/apache2.service"
                    "/etc/rc3.d/S01apache2"
                    "/etc/rc3.d/K01apache-htcacheclean"
                    "/etc/cron.daily/apache2"
                    "/etc/ufw/applications.d/apache2"
                    "/etc/ufw/applications.d/apache2-utils.ufw.profile"
                    "/etc/rc1.d/K01apache-htcacheclean"
                    "/etc/rc1.d/K01apache2"
                    "/etc/rc4.d/S01apache2"
                    "/etc/rc4.d/K01apache-htcacheclean"
                    "/etc/rc0.d/K01apache-htcacheclean"
                    "/etc/rc0.d/K01apache2"
                    "/etc/init.d/apache-htcacheclean"
                    "/etc/init.d/apache2"
                    "/etc/apparmor.d/abstractions/apache2-common"
                    "/etc/rc6.d/K01apache-htcacheclean"
                    "/etc/rc6.d/K01apache2"
                    "/etc/default/apache-htcacheclean"
                    "/var/lib/apache2"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/apache2.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/apache2.service.dsh-also"
                    "/var/lib/systemd/deb-systemd-helper-enabled/apache-htcacheclean.service.dsh-also"
                    "/var/lib/dpkg/info/apache2-bin.md5sums"
                    "/var/lib/dpkg/info/apache2.postrm"
                    "/var/lib/dpkg/info/apache2.conffiles"
                    "/var/lib/dpkg/info/apache2.preinst"
                    "/var/lib/dpkg/info/apache2-utils.list"
                    "/var/lib/dpkg/info/apache2-data.md5sums"
                    "/var/lib/dpkg/info/libapache2-mod-wsgi-py3.postrm"
                    "/var/lib/dpkg/info/apache2-bin.list"
                    "/var/lib/dpkg/info/libapache2-mod-wsgi-py3.list"
                    "/var/lib/dpkg/info/apache2-data.list"
                    "/var/lib/dpkg/info/apache2.postinst"
                    "/var/lib/dpkg/info/apache2.md5sums"
                    "/var/lib/dpkg/info/apache2.list"
                    "/var/lib/dpkg/info/apache2.prerm"
                    "/var/lib/dpkg/info/apache2-utils.md5sums"
                    "/var/cache/apt/archives/libapache2-mod-wsgi-py3_4.9.0-1ubuntu0.1_amd64.deb"
                    "/var/cache/apt/archives/apache2-data_2.4.52-1ubuntu4.12_all.deb"
                    "/var/cache/apt/archives/apache2_2.4.52-1ubuntu4.12_amd64.deb"
                    "/var/cache/apt/archives/apache2-bin_2.4.52-1ubuntu4.12_amd64.deb"
                    "/var/cache/apt/archives/apache2-utils_2.4.52-1ubuntu4.12_amd64.deb"
                    "/var/cache/apache2"
                    "/var/log/apache2"
                    "/var/crash/apache2.0.crash"
                    "/usr/sbin/apache2"
                    "/usr/sbin/apache2ctl"
                    "/usr/sbin/apachectl"
                    "/usr/lib/apache2"
                    "/usr/lib/systemd/system/apache2@.service"
                    "/usr/lib/systemd/system/apache2.service"
                    "/usr/lib/systemd/system/apache-htcacheclean.service"
                    "/usr/lib/systemd/system/apache-htcacheclean@.service"
                    "/usr/share/bug/apache2"
                    "/usr/share/bug/apache2-bin"
                    "/usr/share/apache2"
                    "/usr/share/doc/apache2"
                    "/usr/share/doc/apache2-bin"
                    "/usr/share/doc/apache2-utils"
                    "/usr/share/doc/apache2-data"
                    "/run/apache2"
                    "/run/systemd/propagate/apache2.service"
                    "/run/lock/apache2"
                )
                for _PATH in ${_CMD[@]}; do
                    if [[ -d ${_PATH} ]] || [[ -f ${_PATH} ]]; then
                        run_cmd "rm -rf ${_PATH}"
                    fi
                done
            fi
        else
            exit 1
        fi

        ### ETCD 서비스 종료
        disable_svc "etcd"
        if [ $? -eq 0 ]; then
            remove_pkg "etcd"
            if [ $? -eq 1 ]; then
                exit 1
            else
                _CMD=(
                    "/var/lib/systemd/deb-systemd-helper-masked/etcd.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/etcd.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/etcd2.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/etcd.service.dsh-also"
                    "/var/lib/dpkg/info/etcd-server.postrm"
                    "/var/lib/dpkg/info/etcd-server.list"
                    "/var/lib/etcd"
                    "/etc/rc2.d/K01etcd"
                    "/etc/rc5.d/K01etcd"
                    "/etc/systemd/system/etcd.service"
                    "/etc/rc3.d/K01etcd"
                    "/etc/rc1.d/K01etcd"
                    "/etc/rc4.d/K01etcd"
                    "/etc/rc0.d/K01etcd"
                    "/etc/init.d/etcd"
                    "/etc/rc6.d/K01etcd"
                    "/etc/default/etcd"
                    "/etc/default/etcd.org"
                )
                for _PATH in ${_CMD[@]}; do
                    if [[ -d ${_PATH} ]] || [[ -f ${_PATH} ]]; then
                        run_cmd "rm -rf ${_PATH}"
                    fi
                done
            fi
        else
            exit 1
        fi

        ### RabbitMQ 서비스 종료
        disable_svc "rabbitmq-server"
        if [ $? -eq 0 ]; then
            remove_pkg "rabbitmq-server"
            if [ $? -eq 1 ]; then
                exit 1
            else
                _CMD=(
                    "/etc/rc2.d/K01rabbitmq-server"
                    "/etc/rc5.d/K01rabbitmq-server"
                    "/etc/logrotate.d/rabbitmq-server"
                    "/etc/systemd/system/rabbitmq-server.service"
                    "/etc/rc3.d/K01rabbitmq-server"
                    "/etc/filebeat/modules.d/rabbitmq.yml.disabled"
                    "/etc/rc1.d/K01rabbitmq-server"
                    "/etc/rc4.d/K01rabbitmq-server"
                    "/etc/rc0.d/K01rabbitmq-server"
                    "/etc/init.d/rabbitmq-server"
                    "/etc/rabbitmq"
                    "/etc/rabbitmq/rabbitmq-env.conf"
                    "/etc/rc6.d/K01rabbitmq-server"
                    "/etc/default/rabbitmq-server"
                    "/var/lib/systemd/deb-systemd-helper-masked/rabbitmq-server.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/rabbitmq-server.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/rabbitmq-server.service.dsh-also"
                    "/var/lib/dpkg/info/rabbitmq-server.postrm"
                    "/var/lib/dpkg/info/rabbitmq-server.list"
                    "/var/lib/rabbitmq"
                    "/var/log/rabbitmq"
                )
                for _PATH in ${_CMD[@]}; do
                    if [[ -d ${_PATH} ]] || [[ -f ${_PATH} ]]; then
                        run_cmd "rm -rf ${_PATH}"
                    fi
                done
            fi
        else
            exit 1
        fi

        ### Memcache 서비스 종료
        disable_svc "memcached"
        if [ $? -eq 0 ]; then
            remove_pkg "memcached" "python3-memcache"
            if [ $? -eq 1 ]; then
                exit 1
            else
                _CMD=(
                    "/etc/rc2.d/K01memcached"
                    "/etc/rc5.d/K01memcached"
                    "/etc/memcached.conf"
                    "/etc/systemd/system/memcached.service"
                    "/etc/rc3.d/K01memcached"
                    "/etc/rc1.d/K01memcached"
                    "/etc/rc4.d/K01memcached"
                    "/etc/rc0.d/K01memcached"
                    "/etc/init.d/memcached"
                    "/etc/rc6.d/K01memcached"
                    "/etc/default/memcached"
                    "/var/lib/systemd/deb-systemd-helper-masked/memcached.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/memcached.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/memcached.service.dsh-also"
                    "/var/lib/dpkg/info/memcached.postrm"
                    "/var/lib/dpkg/info/memcached.list"
                    "/run/memcached"
                    "/run/systemd/propagate/memcached.service"
                )
                for _PATH in ${_CMD[@]}; do
                    if [[ -d ${_PATH} ]] || [[ -f ${_PATH} ]]; then
                        run_cmd "rm -rf ${_PATH}"
                    fi
                done
            fi
        else
            exit 1
        fi

        ### MariaDB 서비스 종료
        disable_svc "mariadb"
        if [ $? -eq 0 ]; then
            remove_pkg "mariadb-server" "python3-pymysql"
            if [ $? -eq 1 ]; then
                exit 1
            else
                _CMD=(
                    "/etc/mysql"
                    "/etc/rc2.d/K01mariadb"
                    "/etc/rc5.d/K01mariadb"
                    "/etc/logcheck/ignore.d.server/mariadb-server-10_6"
                    "/etc/logcheck/ignore.d.workstation/mariadb-server-10_6"
                    "/etc/logcheck/ignore.d.paranoid/mariadb-server-10_6"
                    "/etc/logrotate.d/mariadb"
                    "/etc/systemd/system/multi-user.target.wants/mariadb.service"
                    "/etc/systemd/system/mariadb.service"
                    "/etc/rc3.d/K01mariadb"
                    "/etc/rc1.d/K01mariadb"
                    "/etc/rc4.d/K01mariadb"
                    "/etc/rc0.d/K01mariadb"
                    "/etc/init.d/mariadb"
                    "/etc/apparmor.d/usr.sbin.mariadbd"
                    "/etc/rc6.d/K01mariadb"
                    "/var/lib/systemd/deb-systemd-helper-masked/mariadb.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/multi-user.target.wants/mariadb.service"
                    "/var/lib/systemd/deb-systemd-helper-enabled/mariadb.service.dsh-also"
                    "/var/lib/dpkg/info/mariadb-client-10.6.list"
                    "/var/lib/dpkg/info/mariadb-common.postrm"
                    "/var/lib/dpkg/info/mariadb-server-10.6.list"
                    "/var/lib/dpkg/info/mariadb-server-10.6.postrm"
                    "/var/lib/dpkg/info/mariadb-client-10.6.postrm"
                    "/var/lib/dpkg/info/mariadb-common.list"
                    "/var/cache/apt/archives/mariadb-server-core-10.6_1%3a10.6.18-0ubuntu0.22.04.1_amd64.deb"
                    "/var/cache/apt/archives/mariadb-server-10.6_1%3a10.6.18-0ubuntu0.22.04.1_amd64.deb"
                    "/var/cache/apt/archives/mariadb-client-10.6_1%3a10.6.18-0ubuntu0.22.04.1_amd64.deb"
                    "/var/cache/apt/archives/mariadb-client-core-10.6_1%3a10.6.18-0ubuntu0.22.04.1_amd64.deb"
                    "/var/cache/apt/archives/mariadb-server_1%3a10.6.18-0ubuntu0.22.04.1_all.deb"
                    "/var/cache/apt/archives/mariadb-common_1%3a10.6.18-0ubuntu0.22.04.1_all.deb"
                    "/var/crash/mariadb-common.0.crash"
                    "/run/systemd/propagate/mariadb.service"
                )
                for _PATH in ${_CMD[@]}; do
                    if [[ -d ${_PATH} ]] || [[ -f ${_PATH} ]]; then
                        run_cmd "rm -rf ${_PATH}"
                    fi
                done
            fi
        else
            exit 1
        fi

    elif [ ${SVR_MODE} == "compute" ]; then
        ### Neutron 서비스 종료
        disable_svc "neutron-openvswitch-agent"
        if [ $? -eq 0 ]; then
            remove_pkg "neutron-openvswitch-agent"
            if [ $? -eq 1 ]; then
                exit 1
            fi
        else
            exit 1
        fi

        ### Nova 서비스 종료
        disable_svc "nova-compute"
        if [ $? -eq 0 ]; then
            remove_pkg "nova-compute"
            if [ $? -eq 1 ]; then
                exit 1
            else
                remove_pkg "python3-openstackclient"
                if [ $? -eq 1 ]; then
                    exit 1
                fi
            fi
        else
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

    run_cmd "cat <<EOF >${SCRIPT_DIR}/adminrc
export OS_PROJECT_DOMAIN_NAME=Default
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=\"${ADMIN_PASS}\"
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF"
    if [ -f ${SCRIPT_DIR}/adminrc ]; then
        run_cmd "source ${SCRIPT_DIR}/adminrc"
    fi


    if [ ${MODE} == "install" ]; then
        if [ ${SVR_MODE} == "controller" ]; then
            install_ntp
            install_openstack_client
            install_mysql
            install_mysql_python
            install_rabbitmq
            install_memcached
            install_etcd
            install_keystone
            install_glance
            install_placement
            install_nova
            install_neutron
            install_horizon

        elif [ ${SVR_MODE} == "compute" ]; then
            install_ntp
            install_openstack_client
            install_nova
            install_neutron

        else
            log_msg "FAIL" "Please check option -m [ supported 'controller' or 'compute' ]."
            help_usage
            exit 1
        fi

    elif [ ${MODE} == "remove" ]; then
        remove_openstack
    else
        log_msg "ERROR" "Bug abort."
        exit 1
    fi
}

main $*