#!/bin/bash -ex
#

source config.cfg

#
echo "##### Install python openstack client ##### "
apt-get -y install python-openstackclient

echo "##### Install NTP ##### "

apt-get install ntp -y
apt-get install python-mysqldb -y
#
echo "##### Backup NTP configuration... ##### "
sleep 7 
cp /etc/ntp.conf /etc/ntp.conf.bka
rm /etc/ntp.conf
cat /etc/ntp.conf.bka | grep -v ^# | grep -v ^$ >> /etc/ntp.conf
#
sed -i 's/server 0.ubuntu.pool.ntp.org/ \
#server 0.ubuntu.pool.ntp.org/g' /etc/ntp.conf

sed -i 's/server 1.ubuntu.pool.ntp.org/ \
#server 1.ubuntu.pool.ntp.org/g' /etc/ntp.conf

sed -i 's/server 2.ubuntu.pool.ntp.org/ \
#server 2.ubuntu.pool.ntp.org/g' /etc/ntp.conf

sed -i 's/server 3.ubuntu.pool.ntp.org/ \
#server 3.ubuntu.pool.ntp.org/g' /etc/ntp.conf

sed -i "s/server ntp.ubuntu.com/server $CON_MGNT_IP iburst/g" /etc/ntp.conf

sleep 5
echo "##### Installl package for NOVA"
apt-get -y install nova-compute 
echo "libguestfs-tools        libguestfs/update-appliance     boolean true"  | debconf-set-selections

apt-get -y install libguestfs-tools sysfsutils guestfsd python-guestfs

#fix loi chen pass tren hypervisor la KVM
update-guestfs-appliance
chmod 0644 /boot/vmlinuz*
usermod -a -G kvm root

echo "############ Configuring in nova.conf ...############"
sleep 5
########
#/* Sao luu truoc khi sua file nova.conf
filenova=/etc/nova/nova.conf
test -f $filenova.orig || cp $filenova $filenova.orig

#Chen noi dung file /etc/nova/nova.conf vao 
cat << EOF > $filenova
[DEFAULT]
dhcpbridge_flagfile=/etc/nova/nova.conf
dhcpbridge=/usr/bin/nova-dhcpbridge
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova
force_dhcp_release=True
libvirt_use_virtio_for_bridges=True
verbose=True
ec2_private_dns_show_ip=True
api_paste_config=/etc/nova/api-paste.ini
enabled_apis=ec2,osapi_compute,metadata

rpc_backend = rabbit
auth_strategy = keystone
my_ip = $COM1_MGNT_IP

network_api_class = nova.network.neutronv2.api.API
security_group_api = neutron
linuxnet_interface_driver = nova.network.linux_net.NeutronLinuxBridgeInterfaceDriver
firewall_driver = nova.virt.firewall.NoopFirewallDriver

verbose = True

enable_instance_password = True

[oslo_messaging_rabbit]
rabbit_host = $CON_MGNT_IP
rabbit_userid = openstack
rabbit_password = $RABBIT_PASS

[keystone_authtoken]
auth_uri = http://$CON_MGNT_IP:5000
auth_url = http://$CON_MGNT_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = nova
password = $KEYSTONE_PASS

[vnc]
enabled = True
vncserver_listen = 0.0.0.0
vncserver_proxyclient_address = \$my_ip
novncproxy_base_url = http://$CON_EXT_IP:6080/vnc_auto.html

[glance]
host = $CON_MGNT_IP

[oslo_concurrency]
lock_path = /var/lib/nova/tmp

[neutron]
url = http://$CON_MGNT_IP:9696
auth_url = http://$CON_MGNT_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
region_name = RegionOne
project_name = service
username = neutron
password = $NEUTRON_PASS

[libvirt]
inject_key = True
inject_partition = -1
inject_password = True

EOF

echo "##### Restart nova-compute #####"
sleep 5
service nova-compute restart

# Remove default nova db
rm /var/lib/nova/nova.sqlite

echo "##### Install linuxbridge-agent (neutron) on COMPUTE NODE #####"
sleep 10

apt-get -y install neutron-plugin-linuxbridge-agent

echo "Config file neutron.conf"
controlneutron=/etc/neutron/neutron.conf
test -f $controlneutron.orig || cp $controlneutron $controlneutron.orig
rm $controlneutron
touch $controlneutron
cat << EOF >> $controlneutron
[DEFAULT]
core_plugin = ml2

rpc_backend = rabbit
auth_strategy = keystone
verbose = True

[matchmaker_redis]
[matchmaker_ring]
[quotas]
[agent]
root_helper = sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf

[keystone_authtoken]
auth_uri = http://$CON_MGNT_IP:5000
auth_url = http://$CON_MGNT_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = neutron
password = $KEYSTONE_PASS

[database]
# connection = sqlite:////var/lib/neutron/neutron.sqlite

[nova]
[oslo_concurrency]
lock_path = \$state_path/lock
[oslo_policy]
[oslo_messaging_amqp]
[oslo_messaging_qpid]

[oslo_messaging_rabbit]
rabbit_host = $CON_MGNT_IP
rabbit_userid = openstack
rabbit_password = $RABBIT_PASS

[qos]
EOF

echo "############ Configuring Linux Bbridge AGENT ############"
sleep 7 

linuxbridgefile=/etc/neutron/plugins/ml2/linuxbridge_agent.ini 

test -f $linuxbridgefile.orig || cp $linuxbridgefile $linuxbridgefile.orig

cat << EOF >> $linuxbridgefile
[linux_bridge]
physical_interface_mappings = public:eth1

[vxlan]
enable_vxlan = True
local_ip = $COM1_MGNT_IP
l2_population = True

[agent]
prevent_arp_spoofing = True

[securitygroup]
enable_security_group = True
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

EOF

echo "Reset service nova-compute,linuxbridge-agent"
sleep 5
service nova-compute restart
service neutron-plugin-linuxbridge-agent restart


