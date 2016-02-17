#!/bin/bash -ex

source config.cfg

###################
echo "########## START INSTALLING OPS DASHBOARD ##########"
###################
sleep 5

echo "########## Installing Dashboard package ##########"
apt-get -y install openstack-dashboard 
apt-get -y remove --auto-remove openstack-dashboard-ubuntu-theme

echo "########## Creating redirect page ##########"

filehtml=/var/www/html/index.html
test -f $filehtml.orig || cp $filehtml $filehtml.orig
rm $filehtml
touch $filehtml
cat << EOF >> $filehtml
<html>
<head>
<META HTTP-EQUIV="Refresh" Content="0.5; URL=http://$BR_EX_IP/horizon">
</head>
<body>
<center> <h1>Dang chuyen den Dashboard cua OpenStack</h1> </center>
</body>
</html>
EOF
# Allowing insert password in dashboard ( only apply in image )
sed -i "s/'can_set_password': False/'can_set_password': True/g" /etc/openstack-dashboard/local_settings.py

## /* Restarting apache2 and memcached
service apache2 restart
service memcached restart
echo "########## Finish setting up Horizon ##########"

echo "########## LOGIN INFORMATION IN HORIZON ##########"
echo "URL: http://$BR_EX_IP/horizon"
echo "User: admin or demo"
echo "Password:" $ADMIN_PASS