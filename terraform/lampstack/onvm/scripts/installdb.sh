#!/usr/bin/env bash 
# $1 db_username
# $2 db_password

cat /tmp/onvm/hostname | sudo tee -a /etc/hosts >/dev/null
pw=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
sudo apt-get -qqy update
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $pw"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $pw"
sudo apt-get -qqy install mysql-server
echo 'Creating a database...'

mysql -uroot -p$pw -e "CREATE DATABASE decision2016;"
mysql -uroot -p$pw -e "use decision2016; GRANT ALL PRIVILEGES ON decision2016.* TO '$1'@'localhost' IDENTIFIED BY '$2';"
mysql -uroot -p$pw -e "use decision2016; GRANT ALL PRIVILEGES ON decision2016.* TO '$1'@'%' IDENTIFIED BY '$2';"
mysql -uroot -p$pw -e "flush privileges"

cmdStr=$(echo 's/127.0.0.1/database/g')
sudo sed -i -e "${cmdStr}" /etc/mysql/my.cnf

sudo service mysql restart
