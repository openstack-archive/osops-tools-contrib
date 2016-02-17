# Installation and User Guide for OpenStack LIBERTY AIO

### Introduction
- The script is used to install OpenStack LIBERTY on ONLY one server
- Required components:
  - MariaDB, NTP
  - Keystone Version 3
  - Glance
  - Neutron (ML2, OpenvSwitch)
  
### Before you begin
- Install on VMware workstation or physical servers as the following requirements:
```sh
 - RAM: 4GB
 - HDD
  - HDD1: 60GB (used for installing OS and OpenStack components)
  - HDD2: 40GB (used for installing CINDER which provides VOLUME for OpenStack) - NOTE: IF YOU DO NOT INSTALL THIS SERVICE, THIS STEP IS OPTIONAL.
 - 02 NIC with the following order: 
  - NIC 1:  - eth0 - Management Network
  - NIC 2: - eth1 - External Network
 - CPU supports virtulization
```

### Installation steps

#### VMware Environment Preparation
Set up configuration like the following, NOTE THAT:
- NIC1: using Vmnet 1 or hostonly
- NIC2: using bridge
- CPU: 2x2, remebering to select VT

![Topo-liberty](/images/VMware1.png)

#### Option 1: Only use this option during the installation if you choose this one
- After finish the installation steps, if you choose this option remembering to move to the step of using DASHBOARD immediately. Please do not try the second option.

#### Download GIT and configure DHCP for all NICs.
- Using these following commands for network configuration to make sure your server will have enough 02 NICs.
```sh

cat << EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

# NIC MGNT
auto eth0
iface eth0 inet dhcp

# NIC EXT
auto eth1
iface eth1 inet dhcp
EOF

```

- Network restarting
```sh
ifdown -a && ifup -a
```

- Using the `landscape-sysinfo` command to ensure your server had enough 02 NICs. Then check the ip address again on the installed Openstack server.

```sh
root@controller:~# landscape-sysinfo

  System load:  0.93              Users logged in:       1
  Usage of /:   4.0% of 94.11GB   IP address for eth0:   10.10.10.159
  Memory usage: 53%               IP address for eth0  172.16.69.228
  Swap usage:   0%                
```

- Check the Internet connection with the `ping google.com` command.
```sh
root@controller:~# ping google.com

PING google.com (203.162.236.211) 56(84) bytes of data.
64 bytes from 203.162.236.211: icmp_seq=1 ttl=57 time=0.877 ms
64 bytes from 203.162.236.211: icmp_seq=2 ttl=57 time=0.786 ms
64 bytes from 203.162.236.211: icmp_seq=3 ttl=57 time=0.781 ms

```
- Install GIT with root permission
```sh
su -
apt-get update
apt-get -y install git
```

- Execute the script to set up static IP address for the installed OpenStack server.
```sh
git clone https://github.com/vietstacker/openstack-liberty-multinode.git

mv /root/openstack-liberty-multinode/LIBERTY-U14.04-AIO /root
rm -rf openstack-liberty-multinode

cd LIBERTY-U14.04-AIO 
chmod +x *.sh
bash AIO-LIBERTY-1.sh 
```
- The server will be restarted. You need to login again, then execute the next script.
- Execute the script for installing all remaining components.
```sh
bash AIO-LIBERTY-2.sh
```
- Wait for 30-60 minutes for dowloading, configuring the services. Then move to the step of creating network and VMs. 
- Openstack Installation finished here!


#### Option 2:  Execute each script
#### Download and execute the script
- Download script
- Login with root permission, in Ubuntu version of 14.04 you must login with normal user first, then move to the root user using `su - ` command

```sh
git clone https://github.com/vietstacker/openstack-liberty-multinode.git

mv /root/openstack-liberty-multinode/LIBERTY-U14.04-AIO /root
rm -rf openstack-liberty-multinode

cd LIBERTY-U14.04-AIO 
chmod +x *.sh
```

##### Execute the script to set up IP address for all NICs.
- The script will be executed automatically to set up static IP address for all NICs.
```sh
bash 0-liberty-aio-ipadd.sh
```

##### Install NTP, MARIADB, RABBITMQ packages
- Login to the server again with root account. Then do the following scripts.
```sh
su -
cd LIBERTY-U14.04-AIO 
bash 1-liberty-aio-prepare.sh
```
- When the script is executed. The server will be restarted right after that.

##### Install Keystone
- Use the following script to install Keystone
```sh
bash 2-liberty-aio-keystone.sh
```

- Execute the below command to populate environment variables for OpenStack
```sh
source admin-openrc.sh
```

- Use the below script to check whether the installed Keystone is OK or not. 
```sh
openstack token issue
```

- If the result is shown like this. Your installation is succeeded. 
```sh
+------------+----------------------------------+
| Field      | Value                            |
+------------+----------------------------------+
| expires    | 2015-11-20T04:36:40.458714Z      |
| id         | afa93ac41b9f432d989cc6f5c235c44f |
| project_id | a863f6011c9f4d748a9af23983284a90 |
| user_id    | 07817eb3060941598fe406312b8aa448 |
+------------+----------------------------------+
```

##### Install GLANCE
```sh
bash 3-liberty-aio-glance.sh
```

##### Install NOVA
```
bash 4-liberty-aio-nova.sh
```

##### Install NEUTRON
- Install OpenvSwitch and re-configure NIC
```sh
bash 5-liberty-aio-config-ip-neutron.sh
```
- After running the script successfully, your server will be restarted. You need to login with root account in order to finish the bellow script for installing NEUTRON.

```sh
bash 6-liberty-aio-install-neutron.sh
```

##### Install Horizon
```
bash 7-liberty-aio-install-horizon.sh
```

## User Guide for using dashboard to create network, VM, rules.
### Create rule for admin project
- Login to the dashboard
![liberty-horizon1.png](/images/liberty-horizon1.png)

- Select `admin => Access & Security => Manage Rules` tab
![liberty-horizon2.png](/images/liberty-horizon2.png)

- Select `Add Rule` tab
![liberty-horizon3.png](/images/liberty-horizon3.png)

- Open rule which allows user to access to the VMs via SSH
![liberty-horizon4.png](/images/liberty-horizon4.png)
- Do the same with ICMP rule so that ping to virtual machines is allowed and other rules

### Create network
#### Create external network
- Select `Admin => Networks => Create Network`tab
![liberty-net-ext1.png](/images/liberty-net-ext1.png)

- Enter the informatioin and choose like the following image
![liberty-net-ext2.png](/images/liberty-net-ext2.png)

- Click to `ext-net` to declare subnet mask for the external network
![liberty-net-ext3.png](/images/liberty-net-ext3.png)

- Select `Creat Subnet` tab
![liberty-net-ext4.png](/images/liberty-net-ext4.png)

- Initialize IP range for subnet of the external network 
![liberty-net-ext5.png](/images/liberty-net-ext5.png)

- Declare pools and DNS
![liberty-net-ext6.png](/images/liberty-net-ext6.png)

#### Create the internal network
- Select the tabs with the order of `Project admin => Network => Networks => Create Network"
![liberty-net-int1.png](/images/liberty-net-int1.png)

- Initialize for the internal network
![liberty-net-int2.png](/images/liberty-net-int2.png)

- Declare subnet for the internal network
![liberty-net-int3.png](/images/liberty-net-int3.png)

- Declare IP range for the internal network
![liberty-net-int4.png](/images/liberty-net-int4.png)

#### Create a Router for admin project
- Select the tabs with the order of "Project admin => Routers => Create Router
![liberty-r1.png](/images/liberty-r1.png)

- Input router name and do like in the below image
![liberty-r2.png](/images/liberty-r2.png)

- Assign interface for the router
![liberty-r3.png](/images/liberty-r3.png)

![liberty-r4.png](/images/liberty-r4.png)

![liberty-r5.png](/images/liberty-r5.png)
- END the steps of creating exteral network, internal network and router


## Create Instance
- Select the tabs with order of `Project admin => Instances => Launch Instance`
![liberty-instance1.png](/images/liberty-instance1.png)

![liberty-instance2.png](/images/liberty-instance2.png)

![liberty-instance3.png](/images/liberty-instance3.png)
