#!/bin/bash -ex
source config.cfg

apt-get install -y mongodb-server mongodb-clients python-pymongo

sed -i "s/bind_ip = 127.0.0.1/bind_ip = $CON_MGNT_IP/g" /etc/mongodb.conf
service mongodb restart
sleep 40
cat << EOF > mongo.js
  db = db.getSiblingDB("ceilometer");
  db.addUser({user: "ceilometer",
  pwd: "$CEILOMETER_DBPASS",
  roles: [ "readWrite", "dbAdmin" ]})
EOF
sleep 20
mongo --host $CON_MGNT_IP ./mongo.js

## Tao user, endpoint va gan role cho CEILOMETER

openstack user create --password $CEILOMETER_PASS ceilometer
openstack role add --project service --user ceilometer admin
openstack service create --name ceilometer --description "Telemetry" metering

openstack endpoint create \
--publicurl http://$CON_MGNT_IP:8777 \
--internalurl http://$CON_MGNT_IP:8777 \
--adminurl http://$CON_MGNT_IP:8777 \
--region RegionOne \
metering

# Cai dat cac goi trong CEILOMETER

apt-get -y install ceilometer-api ceilometer-collector \
ceilometer-agent-central ceilometer-agent-notification \
ceilometer-alarm-evaluator ceilometer-alarm-notifier \
python-ceilometerclient


mv /etc/ceilometer/ceilometer.conf /etc/ceilometer/ceilometer.conf.bka
cat << EOF > /etc/ceilometer/ceilometer.conf
[DEFAULT]
verbose = True
rpc_backend = rabbit
auth_strategy = keystone

[database]
connection = mongodb://ceilometer:$CEILOMETER_DBPASS@$CON_MGNT_IP:27017/ceilometer

[keystone_authtoken]
auth_uri = http://$CON_MGNT_IP:5000
auth_url = http://$CON_MGNT_IP:35357
auth_plugin = password
project_domain_id = default
user_domain_id = default
project_name = service
username = ceilometer
password = $CEILOMETER_PASS

[service_credentials]
os_auth_url = http://$CON_MGNT_IP:5000/v2.0
os_username = ceilometer
os_tenant_name = service
os_password = $CEILOMETER_PASS
os_endpoint_type = internalURL
os_region_name = RegionOne

# [publisher]
# telemetry_secret = $METERING_SECRET

[matchmaker_redis]

[matchmaker_ring]

[oslo_messaging_amqp]

[oslo_messaging_qpid]

[oslo_messaging_rabbit]
rabbit_host = $CON_MGNT_IP
rabbit_userid = openstack
rabbit_password = $RABBIT_PASS

[oslo_policy]

EOF

echo "Restart service"
sleep 3
service ceilometer-agent-central restart
service ceilometer-agent-notification restart
service ceilometer-api restart
service ceilometer-collector restart
service ceilometer-alarm-evaluator restart
service ceilometer-alarm-notifier restart

echo "Restart service"
sleep 10
service ceilometer-agent-central restart
service ceilometer-agent-notification restart
service ceilometer-api restart
service ceilometer-collector restart
service ceilometer-alarm-evaluator restart
service ceilometer-alarm-notifier restart

