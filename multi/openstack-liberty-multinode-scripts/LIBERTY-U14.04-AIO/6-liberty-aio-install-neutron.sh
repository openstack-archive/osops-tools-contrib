#!/bin/bash -ex
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
  --publicurl http://$LOCAL_IP:9696 \
  --adminurl http://$LOCAL_IP:9696 \
  --internalurl http://$LOCAL_IP:9696 \
  --region RegionOne \
  network 

echo "########## CAI DAT NEUTRON TREN CONTROLLER ##########"
apt-get install -y openvswitch-switch 

apt-get -y install neutron-server python-neutronclient neutron-plugin-ml2 neutron-plugin-openvswitch-agent \
neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent neutron-plugin-openvswitch neutron-common

######## SAO LUU CAU HINH NEUTRON.CONF CHO CONTROLLER##################"
echo "########## Sua lai file neutron.conf ##########"

controlneutron=/etc/neutron/neutron.conf
test -f $controlneutron.orig || cp $controlneutron $controlneutron.orig
rm $controlneutron
cat << EOF > $controlneutron
[DEFAULT]
verbose = True

rpc_backend = rabbit
auth_strategy = keystone

core_plugin = ml2
service_plugins = router
allow_overlapping_ips = True

notify_nova_on_port_status_changes = True
notify_nova_on_port_data_changes = True
nova_url = http://$LOCAL_IP:8774/v2

[matchmaker_redis]
[matchmaker_ring]
[quotas]
[agent]
root_helper = sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf

[keystone_authtoken]
auth_uri = http://$LOCAL_IP:5000
auth_url = http://$LOCAL_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = neutron
password = $NEUTRON_PASS

[database]
connection = mysql+pymysql://neutron:$NEUTRON_DBPASS@$LOCAL_IP/neutron

[nova]
auth_url = http://$LOCAL_IP:35357
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
rabbit_host = $LOCAL_IP
rabbit_userid = openstack
rabbit_password = $RABBIT_PASS

EOF


######## SAO LUU CAU HINH ML2 CHO CONTROLLER##################"
echo "########## Sau file cau hinh cho ml2_conf.ini ##########"
sleep 7

controlML2=/etc/neutron/plugins/ml2/ml2_conf.ini
test -f $controlML2.orig || cp $controlML2 $controlML2.orig
rm $controlML2

cat << EOF > $controlML2
[ml2]
type_drivers = flat,vlan,gre,vxlan
tenant_network_types = gre
mechanism_drivers = openvswitch

[ml2_type_flat]
flat_networks = external

[ml2_type_vlan]

[ml2_type_gre]
tunnel_id_ranges = 1:1000

[ml2_type_vxlan]
[securitygroup]
enable_security_group = True
enable_ipset = True
firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver

[ovs]
local_ip = $LOCAL_IP
enable_tunneling = True
bridge_mappings = external:br-ex
 
[agent]

tunnel_types = gre
EOF

echo "Fix loi MTU"
sleep 3
echo "dhcp-option-force=26,1454" > /etc/neutron/dnsmasq-neutron.conf
killall dnsmasq


######## SAO LUU CAU HINH METADATA CHO CONTROLLER##################"
echo "########## Sua file cau hinh metadata_agent.ini ##########"
sleep 7

metadatafile=/etc/neutron/metadata_agent.ini
test -f $metadatafile.orig || cp $metadatafile $metadatafile.orig
rm $metadatafile
cat << EOF > $metadatafile
[DEFAULT]
verbose = True

auth_uri = http://$LOCAL_IP:5000
auth_url = http://$LOCAL_IP:35357
auth_region = RegionOne
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = neutron
password = $NEUTRON_PASS

nova_metadata_ip = $LOCAL_IP

metadata_proxy_shared_secret = $METADATA_SECRET

EOF

######## SUA FILE CAU HINH  DHCP ##################"
echo "########## Sua file cau hinh DHCP ##########"
sleep 7

dhcpfile=/etc/neutron/dhcp_agent.ini 
test -f $dhcpfile.orig || cp $dhcpfile $dhcpfile.orig
rm $dhcpfile
cat << EOF > $dhcpfile
[DEFAULT]
use_namespaces = True
interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = True
verbose = True
dnsmasq_config_file = /etc/neutron/dnsmasq-neutron.conf

[AGENT]

EOF

###################### SAO LUU CAU HINH L3 ###########################"
echo "########## Sua file cau hinh l3_agent.ini ##########"
sleep 7


l3file=/etc/neutron/l3_agent.ini
test -f $l3file.orig || cp $l3file $l3file.orig
rm $l3file
touch $l3file
cat << EOF >> $l3file
[DEFAULT]
verbose = True
interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver
external_network_bridge =
router_delete_namespaces = True
EOF

chown root:neutron /etc/neutron/*
chown root:neutron $controlML2

su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
  
  

echo "########## KHOI DONG LAI NEUTRON        ##########"
sleep 5
# for i in $( ls /etc/init.d/neutron-* ); do service `basename $i` restart; done
service neutron-server restart
service neutron-l3-agent restart
service neutron-dhcp-agent restart
service neutron-metadata-agent restart
service openvswitch-switch restart
service neutron-plugin-openvswitch-agent restart


echo "########## KHOI DONG LAI NEUTRON (lan2) ##########"
sleep 5
# for i in $( ls /etc/init.d/neutron-* ); do service `basename $i` restart; done
service neutron-server restart
service neutron-l3-agent restart
service neutron-dhcp-agent restart
service neutron-metadata-agent restart
service openvswitch-switch restart
service neutron-plugin-openvswitch-agent restart

# Them lenh khoi dong dich vu cua NEUTRON moi khi reboot OpenStack de fix loi.
sed -i "s/exit 0/# exit 0/g" /etc/rc.local
echo "service neutron-server restart" >> /etc/rc.local
echo "service neutron-l3-agent restart" >> /etc/rc.local
echo "service neutron-dhcp-agent restart" >> /etc/rc.local
echo "service neutron-metadata-agent restart" >> /etc/rc.local
echo "service openvswitch-switch restart" >> /etc/rc.local
echo "service neutron-plugin-openvswitch-agent restart" >> /etc/rc.local
echo "exit 0" >> /etc/rc.local


echo "########## KIEM TRA NEUTRON (cho 60s)   ##########"
# Can doi neutron khoi dong xong de kiem tra
sleep 30
neutron agent-list
