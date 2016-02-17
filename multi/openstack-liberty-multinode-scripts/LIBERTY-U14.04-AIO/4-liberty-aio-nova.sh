#!/bin/bash -ex
#
source config.cfg

echo "Create DB for NOVA "
cat << EOF | mysql -uroot -p$MYSQL_PASS
CREATE DATABASE nova;
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';
FLUSH PRIVILEGES;
EOF


echo "Creat user, endpoint for NOVA"

openstack user create --password $ADMIN_PASS nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute

openstack endpoint create \
--publicurl http://$LOCAL_IP:8774/v2/%\(tenant_id\)s \
--internalurl http://$LOCAL_IP:8774/v2/%\(tenant_id\)s \
--adminurl http://$LOCAL_IP:8774/v2/%\(tenant_id\)s \
--region RegionOne \
compute


echo "########## Install NOVA in $LOCAL_IP ##########"
sleep 5 
apt-get -y install  nova-compute nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler python-novaclient
echo "libguestfs-tools        libguestfs/update-appliance     boolean true"  | debconf-set-selections
apt-get -y install libguestfs-tools sysfsutils guestfsd python-guestfs

#fix loi chen pass tren hypervisor la KVM
update-guestfs-appliance
chmod 0644 /boot/vmlinuz*
usermod -a -G kvm root

######## Backup configurations for NOVA ##########"
sleep 7

#
controlnova=/etc/nova/nova.conf
test -f $controlnova.orig || cp $controlnova $controlnova.orig
rm $controlnova
touch $controlnova
cat << EOF >> $controlnova
[DEFAULT]

rpc_backend = rabbit
auth_strategy = keystone

dhcpbridge_flagfile=/etc/nova/nova.conf
dhcpbridge=/usr/bin/nova-dhcpbridge
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova
force_dhcp_release=True
libvirt_use_virtio_for_bridges=True
ec2_private_dns_show_ip=True
api_paste_config=/etc/nova/api-paste.ini
enabled_apis=ec2,osapi_compute,metadata

my_ip = $LOCAL_IP

network_api_class = nova.network.neutronv2.api.API
security_group_api = neutron
linuxnet_interface_driver = nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver = nova.virt.firewall.NoopFirewallDriver

enabled_apis=osapi_compute,metadata
verbose = True

enable_instance_password = True

[database]
connection = mysql+pymysql://nova:$NOVA_DBPASS@$LOCAL_IP/nova

[oslo_messaging_rabbit]
rabbit_host = $LOCAL_IP
rabbit_userid = openstack
rabbit_password = Welcome123

[keystone_authtoken]
auth_uri = http://$LOCAL_IP:5000
auth_url = http://$LOCAL_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = nova
password = $NOVA_PASS

[vnc]
vncserver_listen = \$my_ip
vncserver_proxyclient_address = \$my_ip
novncproxy_base_url = http://$MASTER:6080/vnc_auto.html

[glance]
host = $LOCAL_IP

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[neutron]
url = http://$LOCAL_IP:9696
auth_url = http://$LOCAL_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
region_name = RegionOne
project_name = service
username = neutron
password = $NEUTRON_PASS

service_metadata_proxy = True
metadata_proxy_shared_secret = $DEFAULT_PASS

[cinder]
os_region_name = RegionOne

[libvirt]
inject_key = True
inject_partition = -1
inject_password = True

EOF

echo "########## Remove Nova default db ##########"
sleep 7
rm /var/lib/nova/nova.sqlite

echo "########## Syncing Nova DB ##########"
sleep 7 
su -s /bin/sh -c "nova-manage db sync" nova


# fix bug libvirtError: internal error: no supported architecture for os type 'hvm'
# echo 'kvm_intel' >> /etc/modules

echo "########## Restarting NOVA ... ##########"
sleep 7 
service nova-api restart; service nova-cert restart; service nova-consoleauth restart; service nova-scheduler restart; service nova-conductor restart; service nova-novncproxy restart; service nova-compute restart; service nova-console restart

sleep 7 
echo "########## Restarting NOVA ... ##########"
service nova-api restart; service nova-cert restart; service nova-consoleauth restart; service nova-scheduler restart; service nova-conductor restart; service nova-novncproxy restart; service nova-compute restart; service nova-console restart

echo "########## Testing NOVA service ##########"
nova-manage service list

