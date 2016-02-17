#!/bin/bash -ex
#
source config.cfg

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

#
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
