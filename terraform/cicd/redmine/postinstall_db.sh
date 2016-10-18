#!/bin/bash

ROOT_DBPASS=$1
REDMINE_DBPASS=$2

# 0. Install dependencies
apt-get update -y
apt-get upgrade -y

# 2. Create an empty database and accompanying user
debconf-set-selections <<< "mysql-server mysql-server/root_password password ${ROOT_DBPASS}"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${ROOT_DBPASS}"
apt-get install -y mariadb-server

mysql -uroot -p${ROOT_DBPASS} -e "CREATE DATABASE redmine CHARACTER SET utf8;"
mysql -uroot -p${ROOT_DBPASS} -e "GRANT ALL PRIVILEGES ON redmine.* TO 'redmine'@'%' IDENTIFIED BY '${REDMINE_DBPASS}';";

sed -i "s|127.0.0.1|0.0.0.0|g" /etc/mysql/my.cnf
service mysql restart
sleep 5
echo -e "${ROOT_DBPASS}\nn\nY\nY\nY\n" | mysql_secure_installation
