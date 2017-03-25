#Show free IP via neutron openstack client
neutron floatingip-list | grep -v "10.*.*." | grep -v "192.168.*.*" | grep -v "172.*.*.*"  | awk '{ print $5 }' | wc -l


#List all allocated IP from nova openstack client
nova list --all-tenants | awk -F"|" '{ print$8 }' | awk -F"," '{ print $2 }' | grep -v -e '^$'
