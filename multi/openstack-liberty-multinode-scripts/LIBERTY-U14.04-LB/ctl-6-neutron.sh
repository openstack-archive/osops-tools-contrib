#!/bin/bash -ex
#
# RABBIT_PASS=a
# ADMIN_PASS=a

source config.cfg

echo "Create DB for NEUTRON "
cat << EOF | mysql -uroot -p$MYSQL_PASS
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';
FLUSH PRIVILEGES;
EOF


echo "Create  user, endpoint for NEUTRON"
openstack user create --password $ADMIN_PASS neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
 
openstack endpoint create \
  --publicurl http://$CON_MGNT_IP:9696 \
  --adminurl http://$CON_MGNT_IP:9696 \
  --internalurl http://$CON_MGNT_IP:9696 \
  --region RegionOne \
  network 
  
# SERVICE_TENANT_ID=`keystone tenant-get service | awk '$2~/^id/{print $4}'`


echo "########## Install NEUTRON in $CON_MGNT_IP or NETWORK node ################"
sleep 5
apt-get -y install neutron-server neutron-plugin-ml2 \
neutron-plugin-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent \
neutron-metadata-agent python-neutronclient


######## Backup configuration NEUTRON.CONF in $CON_MGNT_IP##################"
echo "########## Config NEUTRON in $CON_MGNT_IP/NETWORK node ##########"
sleep 7

#
controlneutron=/etc/neutron/neutron.conf
test -f $controlneutron.orig || cp $controlneutron $controlneutron.orig
rm $controlneutron
touch $controlneutron
cat << EOF >> $controlneutron
[DEFAULT]
core_plugin = ml2
service_plugins = router
allow_overlapping_ips = True
rpc_backend = rabbit

auth_strategy = keystone

notify_nova_on_port_status_changes = True
notify_nova_on_port_data_changes = True
nova_url = http://$CON_MGNT_IP:8774/v2

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
password = $NEUTRON_PASS


[database]
connection = mysql+pymysql://neutron:$NEUTRON_DBPASS@$CON_MGNT_IP/neutron


[nova]
auth_url = http://$CON_MGNT_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
region_name = RegionOne
project_name = service
username = nova
password = $NOVA_PASS

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


######## Backup configuration of ML2 in $CON_MGNT_IP##################"
echo "########## Configuring ML2 in $CON_MGNT_IP/NETWORK node ##########"
sleep 7

controlML2=/etc/neutron/plugins/ml2/ml2_conf.ini
test -f $controlML2.orig || cp $controlML2 $controlML2.orig
rm $controlML2
touch $controlML2

cat << EOF >> $controlML2
[ml2]
tenant_network_types = vxlan
type_drivers = flat,vlan,vxlan
mechanism_drivers = linuxbridge,l2population
extension_drivers = port_security


[ml2_type_flat]
flat_networks = external

[ml2_type_vlan]

[ml2_type_gre]
[ml2_type_vxlan]
vni_ranges = 1:1000

[ml2_type_geneve]
[securitygroup]
enable_ipset = True

EOF

echo "############ Configuring Linux Bbridge AGENT ############"
sleep 7 

linuxbridgefile=/etc/neutron/plugins/ml2/linuxbridge_agent.ini 

test -f $linuxbridgefile.orig || cp $linuxbridgefile $linuxbridgefile.orig

cat << EOF >> $linuxbridgefile
[linux_bridge]
physical_interface_mappings = external:eth1

[vxlan]
enable_vxlan = True
local_ip = $CON_MGNT_IP
l2_population = True


[agent]
prevent_arp_spoofing = True


[securitygroup]
enable_security_group = True
firewall_driver = neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

EOF


echo "############ Configuring L3 AGENT ############"
sleep 7 
netl3agent=/etc/neutron/l3_agent.ini

test -f $netl3agent.orig || cp $netl3agent $netl3agent.orig
rm $netl3agent
touch $netl3agent

cat << EOF >> $netl3agent
[DEFAULT]
interface_driver = neutron.agent.linux.interface.BridgeInterfaceDriver
external_network_bridge =
verbose = True


[AGENT]

EOF


echo "############  Configuring DHCP AGENT ############ "
sleep 7 
#
netdhcp=/etc/neutron/dhcp_agent.ini

test -f $netdhcp.orig || cp $netdhcp $netdhcp.orig
rm $netdhcp
touch $netdhcp

cat << EOF >> $netdhcp
[DEFAULT]
interface_driver = neutron.agent.linux.interface.BridgeInterfaceDriver
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = True

verbose = True
dnsmasq_config_file = /etc/neutron/dnsmasq-neutron.conf

[AGENT]

EOF

echo "Fix loi MTU"
sleep 3
echo "dhcp-option-force=26,1450" > /etc/neutron/dnsmasq-neutron.conf
killall dnsmasq


echo "############  Configuring METADATA AGENT ############"
sleep 7 
netmetadata=/etc/neutron/metadata_agent.ini

test -f $netmetadata.orig || cp $netmetadata $netmetadata.orig
rm $netmetadata
touch $netmetadata

cat << EOF >> $netmetadata
[DEFAULT]
verbose = True

auth_uri = http://$CON_MGNT_IP:5000
auth_url = http://$CON_MGNT_IP:35357
auth_region = regionOne
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = neutron
password = $NEUTRON_PASS

nova_metadata_ip = $CON_MGNT_IP

metadata_proxy_shared_secret = $METADATA_SECRET

EOF
#


su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
  
echo "########## Restarting NOVA service ##########"
sleep 7 
service nova-api restart
service nova-scheduler restart
service nova-conductor restart

echo "########## Restarting NEUTRON service ##########"
sleep 7 
service neutron-server restart
service neutron-plugin-linuxbridge-agent restart
service neutron-dhcp-agent restart
service neutron-metadata-agent restart
service neutron-l3-agent restart

rm -f /var/lib/neutron/neutron.sqlite

echo "Setup IP for PUBLIC interface"
sleep 5


cat << EOF > /etc/network/interfaces
#Assign IP for Controller node

# LOOPBACK NET 
auto lo
iface lo inet loopback

# MGNT NETWORK
auto eth0
iface eth0 inet static
address $CON_MGNT_IP
netmask $NETMASK_ADD_MGNT


# EXT NETWORK
auto eth1:0
iface eth1:0 inet static
address $CON_EXT_IP
netmask $NETMASK_ADD_EXT
gateway $GATEWAY_IP_EXT
dns-nameservers 8.8.8.8


auto eth1
iface  eth1 inet manual
up ip link set dev \$IFACE up
down ip link set dev \$IFACE down

EOF

ifdown -a && ifup -a

echo "#### Reboot ####":
reboot
