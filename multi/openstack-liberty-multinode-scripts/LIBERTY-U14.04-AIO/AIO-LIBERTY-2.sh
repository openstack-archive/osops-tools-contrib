#!/bin/bash -ex 

source config.cfg

#**********************************************************************************#
#################### Python clientNTP, MARIADB, RabbitMQ ########################### 
#**********************************************************************************#
echo "Install python client"
apt-get -y install python-openstackclient
sleep 5

echo "Install and config NTP"
sleep 3 
apt-get install ntp -y
cp /etc/ntp.conf /etc/ntp.conf.bka
rm /etc/ntp.conf
cat /etc/ntp.conf.bka | grep -v ^# | grep -v ^$ >> /etc/ntp.conf


## Config NTP in LIBERTY
sed -i 's/server ntp.ubuntu.com/ \
server 0.vn.pool.ntp.org iburst \
server 1.asia.pool.ntp.org iburst \
server 2.asia.pool.ntp.org iburst/g' /etc/ntp.conf

sed -i 's/restrict -4 default kod notrap nomodify nopeer noquery/ \
#restrict -4 default kod notrap nomodify nopeer noquery/g' /etc/ntp.conf

sed -i 's/restrict -6 default kod notrap nomodify nopeer noquery/ \
restrict -4 default kod notrap nomodify \
restrict -6 default kod notrap nomodify/g' /etc/ntp.conf

# sed -i 's/server/#server/' /etc/ntp.conf
# echo "server $LOCAL_IP" >> /etc/ntp.conf

##############################################
echo "Install and Config RabbitMQ"
sleep 3

apt-get install rabbitmq-server -y
rabbitmqctl add_user openstack $RABBIT_PASS
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
# rabbitmqctl change_password guest $RABBIT_PASS
sleep 3

service rabbitmq-server restart
echo "Finish setup pre-install package !!!"

echo "##### Install MYSQL #####"
sleep 3

echo mysql-server mysql-server/root_password password $MYSQL_PASS | debconf-set-selections
echo mysql-server mysql-server/root_password_again password $MYSQL_PASS | debconf-set-selections
apt-get -y install mariadb-server python-mysqldb curl 

echo "##### Configuring MYSQL #####"
sleep 3


echo "########## CONFIGURING FOR MYSQL ##########"
sleep 5
touch /etc/mysql/conf.d/mysqld_openstack.cnf
cat << EOF > /etc/mysql/conf.d/mysqld_openstack.cnf

[mysqld]
bind-address = 0.0.0.0

[mysqld]
default-storage-engine = innodb
innodb_file_per_table
collation-server = utf8_general_ci
init-connect = 'SET NAMES utf8'
character-set-server = utf8

EOF

sleep 5
echo "Restart MYSQL"
service mysql restart

#********************************************************#
####################  KEYSTONE ########################### 
#********************************************************#

echo "Create Database for Keystone"

cat << EOF | mysql -uroot -p$MYSQL_PASS
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';
FLUSH PRIVILEGES;
EOF

echo "##### Install keystone #####"
sleep 3
echo "manual" > /etc/init/keystone.override
 
apt-get -y install keystone python-openstackclient apache2 libapache2-mod-wsgi memcached python-memcache
 
#/* Back-up file nova.conf
filekeystone=/etc/keystone/keystone.conf
test -f $filekeystone.orig || cp $filekeystone $filekeystone.orig
 
#Config file /etc/keystone/keystone.conf
cat << EOF > $filekeystone

[DEFAULT]
log_dir = /var/log/keystone

admin_token = $TOKEN_PASS
public_bind_host = $LOCAL_IP
admin_bind_host = $LOCAL_IP

[assignment]
[auth]
[cache]
[catalog]
[cors]
[cors.subdomain]
[credential]
[database]
connection = mysql+pymysql://keystone:$KEYSTONE_DBPASS@$LOCAL_IP/keystone

[domain_config]
[endpoint_filter]
[endpoint_policy]
[eventlet_server]
[eventlet_server_ssl]
[federation]
[fernet_tokens]
[identity]
[identity_mapping]
[kvs]
[ldap]
[matchmaker_redis]
[matchmaker_ring]
[memcache]
servers = localhost:11211

[oauth1]
[os_inherit]
[oslo_messaging_amqp]
[oslo_messaging_qpid]
[oslo_messaging_rabbit]
[oslo_middleware]
[oslo_policy]
[paste_deploy]
[policy]
[resource]
[revoke]
driver = sql

[role]
[saml]
[signing]
[ssl]
[token]
provider = uuid
driver = memcache

[tokenless_auth]
[trust]
[extra_headers]
Distribution = Ubuntu

EOF
 
#
su -s /bin/sh -c "keystone-manage db_sync" keystone
 
echo "#### ServerName $LOCAL_IP#### " >>  /etc/apache2/apache2.conf

 
cat << EOF > /etc/apache2/sites-available/wsgi-keystone.conf
Listen 5000
Listen 35357

<VirtualHost *:5000>
    WSGIDaemonProcess keystone-public processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /usr/bin/keystone-wsgi-public
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>

<VirtualHost *:35357>
    WSGIDaemonProcess keystone-admin processes=5 threads=1 user=keystone group=keystone display-name=%{GROUP}
    WSGIProcessGroup keystone-admin
    WSGIScriptAlias / /usr/bin/keystone-wsgi-admin
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On
    <IfVersion >= 2.4>
      ErrorLogFormat "%{cu}t %M"
    </IfVersion>
    ErrorLog /var/log/apache2/keystone.log
    CustomLog /var/log/apache2/keystone_access.log combined

    <Directory /usr/bin>
        <IfVersion >= 2.4>
            Require all granted
        </IfVersion>
        <IfVersion < 2.4>
            Order allow,deny
            Allow from all
        </IfVersion>
    </Directory>
</VirtualHost>

 
EOF
 
ln -s /etc/apache2/sites-available/wsgi-keystone.conf /etc/apache2/sites-enabled
 
service apache2 restart

rm -f /var/lib/keystone/keystone.db


export OS_TOKEN="$TOKEN_PASS"
export OS_URL=http://$LOCAL_IP:35357/v2.0
 
 
# export OS_SERVICE_TOKEN="$TOKEN_PASS"
# export OS_SERVICE_ENDPOINT="http://$LOCAL_IP:35357/v2.0"
# export SERVICE_ENDPOINT="http://$LOCAL_IP:35357/v2.0"
 
###  Identity service
openstack service create --name keystone --description "OpenStack Identity" identity
### Create the Identity service API endpoint
openstack endpoint create \
--publicurl http://$LOCAL_IP:5000/v2.0 \
--internalurl http://$LOCAL_IP:5000/v2.0 \
--adminurl http://$LOCAL_IP:35357/v2.0 \
--region RegionOne \
identity
 
#### To create tenants, users, and roles ADMIN
openstack project create --description "Admin Project" admin
openstack user create --password  $ADMIN_PASS admin
openstack role create admin
openstack role add --project admin --user admin admin
 
#### To create tenants, users, and roles  SERVICE
openstack project create --description "Service Project" service
 
 
#### To create tenants, users, and roles  DEMO
openstack project create --description "Demo Project" demo
openstack user create --password $ADMIN_PASS demo
 
### Create the user role
openstack role create user
openstack role add --project demo --user demo user
 
#################
 
unset OS_TOKEN OS_URL
 
# Tao bien moi truong
 
echo "export OS_PROJECT_DOMAIN_ID=default" > admin-openrc.sh
echo "export OS_USER_DOMAIN_ID=default" >> admin-openrc.sh
echo "export OS_PROJECT_NAME=admin" >> admin-openrc.sh
echo "export OS_TENANT_NAME=admin" >> admin-openrc.sh
echo "export OS_USERNAME=admin" >> admin-openrc.sh
echo "export OS_PASSWORD=$ADMIN_PASS"  >> admin-openrc.sh
echo "export OS_AUTH_URL=http://$LOCAL_IP:35357/v3" >> admin-openrc.sh
echo "export OS_VOLUME_API_VERSION=2"   >> admin-openrc.sh

sleep 5
echo "########## Execute environment script ##########"
chmod +x admin-openrc.sh
cat  admin-openrc.sh >> /etc/profile
cp  admin-openrc.sh /root/admin-openrc.sh
source admin-openrc.sh

echo "export OS_PROJECT_DOMAIN_ID=default" > demo-openrc.sh
echo "export OS_USER_DOMAIN_ID=default" >> demo-openrc.sh
echo "export OS_PROJECT_NAME=demo" >> demo-openrc.sh
echo "export OS_TENANT_NAME=demo" >> demo-openrc.sh
echo "export OS_USERNAME=demo" >> demo-openrc.sh
echo "export OS_PASSWORD=$ADMIN_PASS"  >> demo-openrc.sh
echo "export OS_AUTH_URL=http://$LOCAL_IP:35357/v3" >> demo-openrc.sh
echo "export OS_VOLUME_API_VERSION=2"  >> demo-openrc.sh
chmod +x demo-openrc.sh
cp  demo-openrc.sh /root/demo-openrc.sh


#*****************************************************#
#################### GLANCE ########################### 
#*****************************************************#

echo "Create the database for GLANCE"
cat << EOF | mysql -uroot -p$MYSQL_PASS
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS';
FLUSH PRIVILEGES;
EOF


sleep 5
echo " Create user, endpoint for GLANCE"

openstack user create --password $ADMIN_PASS glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image service" image

openstack endpoint create \
--publicurl http://$LOCAL_IP:9292 \
--internalurl http://$LOCAL_IP:9292 \
--adminurl http://$LOCAL_IP:9292 \
--region RegionOne \
image

echo "########## Install GLANCE ##########"
apt-get -y install glance python-glanceclient
sleep 10
echo "########## Configuring GLANCE API ##########"
sleep 5 
#/* Back-up file nova.conf
fileglanceapicontrol=/etc/glance/glance-api.conf
test -f $fileglanceapicontrol.orig || cp $fileglanceapicontrol $fileglanceapicontrol.orig
rm $fileglanceapicontrol
touch $fileglanceapicontrol

#Configuring glance config file /etc/glance/glance-api.conf

cat << EOF > $fileglanceapicontrol
[DEFAULT]
notification_driver = noop
verbose = True

[database]
connection = mysql+pymysql://glance:$GLANCE_DBPASS@$LOCAL_IP/glance
backend = sqlalchemy

[glance_store]
default_store = file
filesystem_store_datadir = /var/lib/glance/images/

[image_format]
[keystone_authtoken]
auth_uri = http://$LOCAL_IP:5000
auth_url = http://$LOCAL_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = glance
password = $GLANCE_PASS

[matchmaker_redis]
[matchmaker_ring]
[oslo_concurrency]
[oslo_messaging_amqp]
[oslo_messaging_qpid]
[oslo_messaging_rabbit]
[oslo_policy]
[paste_deploy]
flavor = keystone

[store_type_location_strategy]
[task]
[taskflow_executor]

EOF

#
sleep 10
echo "########## Configuring GLANCE REGISTER ##########"
#/* Backup file file glance-registry.conf
fileglanceregcontrol=/etc/glance/glance-registry.conf
test -f $fileglanceregcontrol.orig || cp $fileglanceregcontrol $fileglanceregcontrol.orig
rm $fileglanceregcontrol
touch $fileglanceregcontrol
#Config file /etc/glance/glance-registry.conf

cat << EOF > $fileglanceregcontrol

[DEFAULT]
notification_driver = noop
verbose = True

[database]
connection = mysql+pymysql://glance:$GLANCE_DBPASS@$LOCAL_IP/glance
backend = sqlalchemy

[glance_store]

[keystone_authtoken]
auth_uri = http://$LOCAL_IP:5000
auth_url = http://$LOCAL_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = glance
password = $GLANCE_PASS

[matchmaker_redis]
[matchmaker_ring]
[oslo_messaging_amqp]
[oslo_messaging_qpid]
[oslo_messaging_rabbit]
[oslo_policy]

[paste_deploy]
flavor = keystone

EOF

sleep 7
echo "########## Remove Glance default DB ##########"
rm /var/lib/glance/glance.sqlite

chown glance:glance $fileglanceapicontrol
chown glance:glance $fileglanceregcontrol

sleep 7
echo "########## Syncing DB for Glance ##########"
glance-manage db_sync

sleep 5
echo "########## Restarting GLANCE service ... ##########"
service glance-registry restart
service glance-api restart
sleep 3
service glance-registry restart
service glance-api restart

echo "Remove glance.sqlite "
rm -f /var/lib/glance/glance.sqlite

sleep 3
echo "########## Registering Cirros IMAGE for GLANCE ... ##########"
mkdir images
cd images/
wget http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img

glance image-create --name "cirros" \
--file cirros-0.3.4-x86_64-disk.img \
--disk-format qcow2 --container-format bare \
--visibility public --progress

cd /root/
# rm -r /tmp/images

sleep 5
echo "########## Testing Glance ##########"
glance image-list

#*****************************************************#
##################### NOVA ############################ 
#*****************************************************#

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
apt-get -y install libguestfs-tools sysfsutils


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
linuxnet_interface_driver = nova.network.linux_net.NeutronLinuxBridgeInterfaceDriver
firewall_driver = nova.virt.firewall.NoopFirewallDriver

enabled_apis=osapi_compute,metadata
verbose = True

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
novncproxy_base_url = http://$BR_EX_IP:6080/vnc_auto.html


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


#**********************************************************#
####################### NEUTRON ############################ 
#**********************************************************#

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

echo "########## CAI DAT NEUTRON ##########"

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


echo "########## KIEM TRA NEUTRON (cho 30s)   ##########"
# Can doi neutron khoi dong xong de kiem tra
sleep 30
neutron agent-list

#**********************************************************#
####################### HORIZON ############################ 
#**********************************************************#
echo "########## Installing Dashboard package ##########"
sleep 5
apt-get -y install openstack-dashboard 

# echo "########## Fix bug in apache2 ##########"
# sleep 5
# Fix bug apache in ubuntu 14.04
# echo "ServerName localhost" > /etc/apache2/conf-available/servername.conf
# sudo a2enconf servername 

echo "########## Creating redirect page ##########"

filehtml=/var/www/html/index.html
test -f $filehtml.orig || cp $filehtml $filehtml.orig
rm $filehtml
touch $filehtml
cat << EOF >> $filehtml
<html>
<head>
<META HTTP-EQUIV="Refresh" Content="0.5; URL=http://$BR_EX_IP/horizon">
</head>
<body>
<center> <h1>Dang chuyen den Dashboard cua OpenStack</h1> </center>
</body>
</html>
EOF
# Allowing insert password in dashboard ( only apply in image )
sed -i "s/'can_set_password': False/'can_set_password': True/g" /etc/openstack-dashboard/local_settings.py

## /* Restarting apache2 and memcached
service apache2 restart
service memcached restart
echo "########## Finish setting up Horizon ##########"

echo "########## LOGIN INFORMATION IN HORIZON ##########"
echo "URL: http://$BR_EX_IP/horizon"
echo "User: admin or demo"
echo "Password:" $ADMIN_PASS


