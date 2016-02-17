#!/bin/bash -ex

source config.cfg

sleep 3
echo "#### Update for Ubuntu #####"

apt-get install software-properties-common -y
add-apt-repository cloud-archive:liberty -y

sleep 3
echo "##### update for Ubuntu #####"
apt-get update -y && apt-get upgrade -y && apt-get dist-upgrade -y

echo "##### Configuring hostname for COMPUTE1 node... #####"
sleep 3
echo "compute1" > /etc/hostname
hostname -F /etc/hostname

iphost=/etc/hosts
test -f $iphost.orig || cp $iphost $iphost.orig
rm $iphost
touch $iphost
cat << EOF >> $iphost
127.0.0.1       localhost
127.0.0.1        compute1
$CON_MGNT_IP    controller
$COM1_MGNT_IP   compute1
EOF

sleep 3
echo "##### Config network for COMPUTE NODE ####"
ifaces=/etc/network/interfaces
test -f $ifaces.orig || cp $ifaces $ifaces.orig
rm $ifaces
touch $ifaces
cat << EOF >> $ifaces
#Dat IP cho $CON_MGNT_IP node

# LOOPBACK NET 
auto lo
iface lo inet loopback

# MGNT NETWORK
auto eth0
iface eth0 inet static
address $COM1_MGNT_IP
netmask $NETMASK_ADD_MGNT


# EXT NETWORK
auto eth1
iface eth1 inet static
address $COM1_EXT_IP
netmask $NETMASK_ADD_EXT
gateway $GATEWAY_IP_EXT
dns-nameservers 8.8.8.8

EOF

sleep 5
echo "##### Rebooting machine ... #####"
init 6
#




