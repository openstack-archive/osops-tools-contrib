#!/usr/bin/env bash
# $1 db_username
# $2 db_password

cat /tmp/onvm/hostname | sudo tee -a /etc/hosts >/dev/null
echo 'Installing apache2 and php 5...'
sudo apt-get -qqy update
sudo apt-get -qqy install apache2 php5 php5-mysql
echo 'ServerName localhost' | sudo tee -a /etc/apache2/apache2.conf >/dev/null

sudo mv /tmp/onvm/app/* /var/www/html
sudo chown -R www-data:www-data /var/www/html
sudo rm -r -f /var/www/html/index.html

cmdStr=$(echo "s/TTTFFFdbuser/$1/g")
sudo sed -i -e "${cmdStr}" /var/www/html/index.php

cmdStr=$(echo "s/TTTFFFdbpass/$2/g")
sudo sed -i -e "${cmdStr}" /var/www/html/index.php
