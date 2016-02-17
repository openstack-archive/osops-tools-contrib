#!/bin/bash -ex 

source config.cfg

echo "########## CONFIGURING STATIC IP FOR NICs ##########"

ifaces=/etc/network/interfaces
test -f $ifaces.orig || cp $ifaces $ifaces.orig
rm $ifaces
cat << EOF > $ifaces
#Configuring IP for Controller node

# LOOPBACK NET 
auto lo
iface lo inet loopback

# LOCAL NETWORK
auto eth0
iface eth0 inet static
address $LOCAL_IP
netmask $NETMASK_LOCAL

# EXT NETWORK
auto eth1
iface eth1 inet static
address $MASTER
netmask $NETMASK_MASTER
gateway $GATEWAY_IP
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
127.0.0.1       localhost controller
$LOCAL_IP   controller

EOF


# Enable IP forwarding
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
echo "net.ipv4.conf.all.rp_filter=0" >> /etc/sysctl.conf
echo "net.ipv4.conf.default.rp_filter=0" >> /etc/sysctl.conf
sysctl -p

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


