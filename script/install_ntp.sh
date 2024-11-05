function install_ntp() {
    check_pkg "chrony"
    if [ $? -eq 0 ]; then
        if [ ! -f /etc/chrony/chrony.conf.org ]; then
            run_cmd "cp -p /etc/chrony/chrony.conf /etc/chrony/chrony.conf.org"
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
