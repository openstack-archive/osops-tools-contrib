#!/bin/bash -ex
source config.cfg


ifaces=/etc/network/interfaces
test -f $ifaces.orig || cp $ifaces $ifaces.orig
rm $ifaces
touch $ifaces
cat << EOF >> $ifaces
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
auto eth1
iface eth1 inet static
address $CON_EXT_IP
netmask $NETMASK_ADD_EXT
gateway $GATEWAY_IP_EXT
dns-nameservers 8.8.8.8
EOF


echo "Configuring hostname in CONTROLLER node"
sleep 3
echo "controller" > /etc/hostname
hostname -F /etc/hostname


echo "Configuring for file /etc/hosts"
sleep 3
iphost=/etc/hosts
test -f $iphost.orig || cp $iphost $iphost.orig
rm $iphost
touch $iphost
cat << EOF >> $iphost
127.0.0.1       localhost
127.0.1.1       controller
$CON_MGNT_IP    controller
$COM1_MGNT_IP   compute1


EOF


echo "##### Cai dat repos cho Liberty ##### "
apt-get install software-properties-common -y
add-apt-repository cloud-archive:liberty -y

sleep 5
echo "UPDATE PACKAGE FOR LIBERTY"
apt-get -y update && apt-get -y upgrade && apt-get -y dist-upgrade

sleep 5

echo "Reboot Server"

#sleep 5
init 6
#


