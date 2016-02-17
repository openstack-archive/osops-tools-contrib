#!/bin/bash -ex
#
# RABBIT_PASS=a
# ADMIN_PASS=a
source config.cfg

echo "Create DB for CINDER"
sleep 5
cat << EOF | mysql -uroot -p$MYSQL_PASS
CREATE DATABASE cinder;
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$CINDER_DBPASS';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$CINDER_DBPASS';
FLUSH PRIVILEGES;
EOF

echo "Create user, endpoint for CINDER"
sleep 5
openstack user create --password $ADMIN_PASS cinder
openstack role add --project service --user cinder admin
openstack service create --name cinder --description \
    "OpenStack Block Storage" volume
openstack service create --name cinderv2 --description \
    "OpenStack Block Storage" volumev2


openstack endpoint create \
--publicurl http://$CON_MGNT_IP:8776/v1/%\(tenant_id\)s \
--internalurl http://$CON_MGNT_IP:8776/v1/%\(tenant_id\)s \
--adminurl http://$CON_MGNT_IP:8776/v1/%\(tenant_id\)s \
--region RegionOne \
volume


openstack endpoint create \
--publicurl http://$CON_MGNT_IP:8776/v2/%\(tenant_id\)s \
--internalurl http://$CON_MGNT_IP:8776/v2/%\(tenant_id\)s \
--adminurl http://$CON_MGNT_IP:8776/v2/%\(tenant_id\)s \
--region RegionOne \
volumev2

#
echo "########## Install CINDER ##########"
sleep 3
apt-get install -y cinder-api cinder-scheduler python-cinderclient \
    lvm2 cinder-volume python-mysqldb qemu


pvcreate /dev/vdb
vgcreate cinder-volumes /dev/vdb
sed -r -i 's#(filter = )(\[ "a/\.\*/" \])#\1["a\/vdb\/", "r/\.\*\/"]#g' \
    /etc/lvm/lvm.conf

filecinder=/etc/cinder/cinder.conf
test -f $filecinder.orig || cp $filecinder $filecinder.orig
rm $filecinder
cat << EOF > $filecinder

[DEFAULT]
rootwrap_config = /etc/cinder/rootwrap.conf
api_paste_confg = /etc/cinder/api-paste.ini
iscsi_helper = tgtadm
volume_name_template = volume-%s
volume_group = cinder-volumes
verbose = True
auth_strategy = keystone
state_path = /var/lib/cinder
lock_path = /var/lock/cinder
volumes_dir = /var/lib/cinder/volumes

rpc_backend = rabbit
my_ip = $CON_MGNT_IP

enabled_backends = lvm

glance_host = $CON_MGNT_IP

notification_driver = messagingv2

[database]
connection = mysql+pymysql://cinder:$CINDER_DBPASS@$CON_MGNT_IP/cinder

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
username = cinder
password = $CINDER_PASS

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp

[cinder]
os_region_name = RegionOne

[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
iscsi_protocol = iscsi
iscsi_helper = tgtadm

EOF



echo "########## Syncing Cinder DB ##########"
sleep 3
su -s /bin/sh -c "cinder-manage db sync" cinder

echo "########## Restarting CINDER service ##########"
sleep 3
service tgt restart
service cinder-volume restart
service cinder-api restart
service cinder-scheduler restart

rm -f /var/lib/cinder/cinder.sqlite

echo "########## Finish setting up CINDER !!! ##########"