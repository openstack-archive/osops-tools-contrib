# Installation Steps

### Prepare LAB enviroment
- Using in VMware Workstation enviroment

#### Configure CONTROLLER NODE
```sh
RAM: 4GB
CPU: 2x2,  VT supported
NIC1: eth0: 10.10.10.0/24 (interntel range, using vmnet or hostonly in VMware Workstation)
NIC2: eth1: 172.16.69.0/24, gateway 172.16.69.1 (external range - using NAT or Bridge VMware Workstation)
HDD: 60GB
```


#### Configure CONTROLLER NODE
```sh
RAM: 4GB
CPU: 2x2, VT supported
NIC1: eth0: 10.10.10.0/24 (interntel range, using vmnet or hostonly in VMware Workstation)
NIC2: eth1: 172.16.69.0/24, gateway 172.16.69.1 (external range - using NAT or Bridge VMware Workstation  )
HDD: 1000GB
```

### Execute script
- Install git package and dowload script 
```sh
su -
apt-get update
apt-get -y install git 

git clone https://github.com/vietstacker/openstack-liberty-multinode.git
mv /root/openstack-liberty-multinode/LIBERTY-U14.04-OVS/ /root/
rm -rf openstack-liberty-multinode/
cd LIBERTY-U14.04-OVS/
chmod +x *.sh

```

## Install on CONTROLLER NODE
### install IP establishment script and repos for Liberty
- Edit file config in dicrectory with IP that you want to use.
 
```sh
bash ctl-1-ipadd.sh
```

### Install NTP, MariaDB packages
```sh
bash ctl-2-prepare.sh
```

### Install KEYSTONE
- Install Keystone
```sh
bash ctl-3.keystone.sh
```

- Declare enviroment parameter
```sh
source admin-openrc.sh
```

### Install GLANCE
```sh
bash ctl-4-glance.sh
```

### Install NOVA
```sh
bash ctl-5-nova.sh
```

### Install NEUTRON
```sh
bash ctl-6-neutron.sh
```
- After NEUTRON installation done, controller node will restart.
- Login with `root` end execute Horizon installation script.

### Install HORIZON
- Login with  `root` privilege and execute script below
```sh
bash ctl-horizon.sh
```

## Install on COMPUTE NODE
### Dowload GIT and script
- install git package and dowload script 
```sh
su -
apt-get update
apt-get -y install git 

git clone https://github.com/vietstacker/openstack-liberty-multinode.git
mv /root/openstack-liberty-multinode/LIBERTY-U14.04-OVS/ /root/
rm -rf openstack-liberty-multinode/
cd LIBERTY-U14.04-OVS/
chmod +x *.sh

### Establish IP and hostname
- Edit file config to make it suitable with your IP.
- Execute script to establish IP, hostname
```sh
bash com1-ipdd.sh
```
- The server will restart after script `com1-ipdd.sh` is executed.
- Login to server with root privilege and execute conponents installation script on Nova

```sh
su -
cd LIBERTY-U14.04-OVS/
bash com1-prepare.sh
```

After install COMPUTE NODE, move to step that guide to use dashboard


## Using dashboard to initialize network, VM, rules.
### Initialize rule for project admin
- Login to dasboard
![liberty-horizon1.png](/images/liberty-horizon1.png)

- Select tab `admin => Access & Security => Manage Rules`
![liberty-horizon2.png](/images/liberty-horizon2.png)

- Select tab `Add Rule`
![liberty-horizon3.png](/images/liberty-horizon3.png)

- Open rule to allow SSH from outside to virtual machine
![liberty-horizon4.png](/images/liberty-horizon4.png)
- Do the same with ICMP rule to allow ping to virtual machine and the other rules.

### Initialize network
#### Initialize external network range
- Select tab `Admin => Networks => Create Network`
![liberty-net-ext1.png](/images/liberty-net-ext1.png)

- Enter and select tabs like picture below.
![liberty-net-ext2.png](/images/liberty-net-ext2.png)

- Click to newly created `ext-net` to declare subnet for external range.
![liberty-net-ext3.png](/images/liberty-net-ext3.png)

- Select tab `Creat Subnet`
![liberty-net-ext4.png](/images/liberty-net-ext4.png)

- Declare IP range of subnet for external range
![liberty-net-ext5.png](/images/liberty-net-ext5.png)

- Declare pools and DNS
![liberty-net-ext6.png](/images/liberty-net-ext6.png)

#### Initialize internal network range
- Select tabs in turn of rank : `Project admin => Network => Networks => Create Network"
![liberty-net-int1.png](/images/liberty-net-int1.png)

- Declare name for internal network
![liberty-net-int2.png](/images/liberty-net-int2.png)

- Declare subnet for internal network
![liberty-net-int3.png](/images/liberty-net-int3.png)

- Declare IP range for Internal network
![liberty-net-int4.png](/images/liberty-net-int4.png)

#### Initialize Router for project admin
- Select by tabs "Project admin => Routers => Create Router
![liberty-r1.png](/images/liberty-r1.png)

- Initialize router name and select like picture below
![liberty-r2.png](/images/liberty-r2.png)

- Apply interface for router
![liberty-r3.png](/images/liberty-r3.png)

![liberty-r4.png](/images/liberty-r4.png)

![liberty-r5.png](/images/liberty-r5.png)
- ending of initializing steps:  exteral network, internal network, router



## Initialize virtual machine (Instance)
- L?a ch?n các tab d??i `Project admin => Instances => Launch Instance`
![liberty-instance1.png](/images/liberty-instance1.png)

![liberty-instance2.png](/images/liberty-instance2.png)

![liberty-instance3.png](/images/liberty-instance3.png)












