#!/bin/bash
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

# Author: Jared King <jareking@cisco.com>
# Date: 2017-01-11
#
#
#v.2
#changed the interface to be a variable throughout the script.
#removed eth1 as the interface to tcpdump on, it seems that there is some variation in the interfaces we use. Focus is now the physical bridge.
#
#Bugs:
#If there is not much traffic, the script does not handle it very well.
#Fix as needed


#Basic usage
if [ -z "$1" ]; then
    echo
    echo usage: $0 net-node
    echo
    echo e.g. $0 net-006
    echo
    echo places blame for high traffic
    exit
fi

IF=$1
# For netnodes we are mainly interested in the phy-br-ex interface at this time.
#Change this to the interface you are interested in.
#might make this an option in a later version
ETH_DEV=phy-br-ex
echo "The current packets packets-per-second:"
#while true

#ssh to target netnde and figure out what the current network stats looks like.
#I hate these variable names, this should be changed
ssh $1 '
for run in {1..10}
do

    TXPPSR1=`cat /sys/class/net/'$ETH_DEV'/statistics/rx_packets`
    TXPPST1=`cat /sys/class/net/'$ETH_DEV'/statistics/tx_packets`

    TBPSR1=`cat /sys/class/net/'$ETH_DEV'/statistics/rx_bytes`
    TBPST1=`cat /sys/class/net/'$ETH_DEV'/statistics/tx_bytes`

    DTBPSR1=`cat /sys/class/net/'$ETH_DEV'/statistics/rx_dropped`
    DTBPST1=`cat /sys/class/net/'$ETH_DEV'/statistics/tx_dropped`

    sleep 1

    TXPPSR2=`cat /sys/class/net/'$ETH_DEV'/statistics/rx_packets`
    TXPPST2=`cat /sys/class/net/'$ETH_DEV'/statistics/tx_packets`

    TBPSR2=`cat /sys/class/net/'$ETH_DEV'/statistics/rx_bytes`
    TBPST2=`cat /sys/class/net/'$ETH_DEV'/statistics/tx_bytes`

    DTBPSR2=`cat /sys/class/net/'$ETH_DEV'/statistics/rx_dropped`
    DTBPST2=`cat /sys/class/net/'$ETH_DEV'/statistics/tx_dropped`


    TXPPS=`expr $TXPPST2 - $TXPPST1`
    RXPPS=`expr $TXPPSR2 - $TXPPSR1`

    TBPS=`expr $TBPST2 - $TBPST1`
    RBPS=`expr $TBPSR2 - $TBPSR1`

    TKBPS=`expr $TBPS / 1024`
    RKBPS=`expr $RBPS / 1024`

    DTBPS=`expr $DTBPST2 - $DTBPST1`
    DRBPS=`expr $DTBPSR2 - $DTBPSR1`

    echo ""

    echo "tx '$ETH_DEV': $TXPPS pkts/s rx '$ETH_DEV': $RXPPS pkts/s"
    echo "tx '$ETH_DEV': $TKBPS kb/s rx '$ETH_DEV': $RKBPS kb/s"
    echo "tx '$ETH_DEV': $DTBPS dropped rx '$ETH_DEV': $DRBPS dropped"

done
'
#tcpdump 20,000 packets and get the mac address of the top packet sender.
#tcpdump on eth1 because it's the physical interface, not sure if all of the traffic would show up if we captured packets on the bridge.
#Put all of this into an array so that it's easier to reference
#limiting the mac addresses to fa: because these are openstack macs
my_array=( $(ssh $1 tcpdump -tnne -c 20000 -i $ETH_DEV  2>/dev/null | awk '{print $1}' | grep fa: | sort -nr| uniq -c | awk ' $1 > 1000 ') )

echo
echo
echo
echo
echo
echo
#Spit out the mac addresses
echo "The offenders mac is:"
for i in "${!my_array[@]}"; do
    ((i%2==1)) && printf "%s\n" "${my_array[i]}"
done
# find the ports of the offending mac addresses
port_array=( $(neutron port-list | grep "${my_array[1]}\|${my_array[3]}"|depipe| awk '{print $1}' ))

echo
echo
echo
#echo them so that we can reference it later.
echo "The ports are:"
for element in "${port_array[@]}"
do
 echo "${element}"
done
#print out some details on the packets we captured
echo
echo
echo "Out of 20,000 packets this host sent:" ${my_array[0]}
echo
neutron port-show "${port_array[0]}"
echo
echo
echo
echo "The tenant to blame is:"
keystone tenant-get $(neutron port-show "${port_array[0]}" | grep tenant | depipe | awk '{print $2}')


echo
echo
echo "Out of 20,000 packets this host sent:" ${my_array[2]}
echo
neutron port-show "${port_array[1]}"


echo
echo
echo
echo "The tenant to blame is:"
keystone tenant-get $(neutron port-show "${port_array[1]}" | grep tenant | depipe | awk '{print $2}')



echo
echo
echo
echo "tcpdump to check traffic types for the top host"
# we found the vlan in the earlier packet capture, and all of the info is logged in the openvswitch-agent.log. This log contains more info if we want.
VLAN_ID=$(ssh $1 grep "${port_array[0]}" /var/log/neutron/openvswitch-agent.log  |grep vlan | head -1 | awk '{print $16}' | cut -d"," -f 1)

echo "The vlan is:"
echo $VLAN_ID

#ssh $1 ip netns exec qrouter-$(neutron port-show ${port_array[0]} cu
# Run another tcpdump of 200 packets and take a look at the for just the vlan we want and print the source, destination and ports/services used.
# There should be a better way to do this, the grep sucks and should be moved into the tcpdump. But I couldn't make it work like I wanted.
echo
echo
echo "Hosts that sent more than 10 packets during the capture"
echo "It is possible for this to be empty on low utilized hosts."
echo
echo "Number of packets | Src Host    |   Dest Host"
echo
ssh $1 tcpdump -te -c 2000 -i $ETH_DEV 2>/dev/null| grep "vlan $VLAN_ID" | awk '{ print $19" "$20" "$21}'  | sort | uniq -c | awk ' $1 > 10 '|sort -nr
echo
echo
echo
echo
###########################################################
# Commenting this out because it seems redundant
#
# Dump what OVS says about the physical interface. Not sure if this needs to be the bridge or the physical interface. More testing is required.
# Ths intent here is to see if OVS is dropping packets.
#echo "OVS Details on br-ex"
echo
# we haven't seen drops on eth1, we normally drop packets on the bridge instead.
#ssh $1 ovs-ofctl dump-ports br-ex | grep -A1 "port  5"
#echo
#echo "OVS Dropped Packets on br-ex over 10 seconds"
#ssh $1 '
#   OVSDROPRX1=`ovs-ofctl dump-ports br-ex | grep "port  5"  | cut -d"," -f3 | sed 's/[^0-9]*//g'`
#   OVSDROPTX1=`ovs-ofctl dump-ports br-ex | grep -A1 "port  5"| grep tx  | cut -d"," -f3 | sed 's/[^0-9]*//g'`
#       sleep 10
#        OVSDROPRX2=`ovs-ofctl dump-ports br-ex | grep "port  5"  | cut -d"," -f3 | sed 's/[^0-9]*//g'`
#   OVSDROPTX2=`ovs-ofctl dump-ports br-ex | grep -A1 "port  5"| grep tx  | cut -d"," -f3 | sed 's/[^0-9]*//g'`
#   OVSDROPDIFRX=`expr $OVSDROPRX2 - $OVSDROPRX1`
#   OVSDROPDIFTX=`expr $OVSDROPTX2 - $OVSDROPTX1`
#   echo "OVS Dropped rx: $OVSDROPDIFRX"
#   echo "OVS Dropped tx: $OVSDROPDIFTX"
#'
#echo
echo
echo "OVS Interface Details"
echo
#Dump interesting physical characteristics of the bridge.
ssh $1 ovs-ofctl dump-ports-desc br-ex

exit 0
