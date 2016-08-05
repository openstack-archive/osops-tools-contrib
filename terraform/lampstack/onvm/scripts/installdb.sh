#!/usr/bin/env bash

cat /tmp/onvm/hostname | sudo tee -a /etc/hosts >/dev/null
sudo apt-get -qqy update
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password password pass'
sudo debconf-set-selections <<< 'mysql-server mysql-server/root_password_again password pass'
sudo apt-get -qqy install mysql-server
echo 'Creating a database...'

mysql -uroot -ppass -e "CREATE DATABASE decision2016;"
mysql -uroot -ppass -e "use decision2016; GRANT ALL PRIVILEGES ON decision2016.* TO 'dbuser'@'localhost' IDENTIFIED BY 'pass';"
mysql -uroot -ppass -e "use decision2016; GRANT ALL PRIVILEGES ON decision2016.* TO 'dbuser'@'%' IDENTIFIED BY 'pass';"
mysql -uroot -ppass -e "flush privileges"

cmdStr=$(echo 's/127.0.0.1/database/g')
sudo sed -i -e "${cmdStr}" /etc/mysql/my.cnf

sudo service mysql restart
