#!/bin/bash -ex 

source config.cfg

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


echo "########## Install and Config OpenvSwitch ##########"
apt-get install -y openvswitch-switch 

echo "########## Cau hinh br-int va br-ex cho OpenvSwitch ##########"
sleep 5
ovs-vsctl add-br br-ex
ovs-vsctl add-port br-ex eth1


echo "########## Cau hinh dia chi IP cho br-ex ##########"
ifaces=/etc/network/interfaces
test -f $ifaces.orig1 || cp $ifaces $ifaces.orig1
rm $ifaces
cat << EOF > $ifaces
# The loopback network interface
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
address $LOCAL_IP
netmask $NETMASK_LOCAL

# The primary network interface
auto br-ex
iface br-ex inet static
address $MASTER
netmask $NETMASK_MASTER
gateway $GATEWAY_IP
dns-nameservers 8.8.8.8

auto eth1
iface eth1 inet manual
 up ifconfig \$IFACE 0.0.0.0 up
 up ip link set \$IFACE promisc on
 down ip link set \$IFACE promisc off
 down ifconfig \$IFACE down
EOF

sleep 5
echo "Reboot Server"

#sleep 5
init 6
