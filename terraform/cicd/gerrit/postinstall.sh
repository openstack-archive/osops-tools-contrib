#!/bin/bash

ROOT_DBPASS=secure
GERRIT_DBPASS=secure
gerrit_version=2.12.4
deployment_folder=/opt/gerrit

# 1. Configure Java for Strong Cryptography
apt-get update -y
apt-get install software-properties-common -y
add-apt-repository ppa:webupd8team/java -y
apt-get update -y

echo debconf shared/accepted-oracle-license-v1-1 select true | debconf-set-selections
echo debconf shared/accepted-oracle-license-v1-1 seen true | debconf-set-selections

apt-get install -y oracle-java8-set-default oracle-java8-unlimited-jce-policy

# 2. Download Gerrit
wget https://www.gerritcodereview.com/download/gerrit-${gerrit_version}.war

# 3. Database Setup
debconf-set-selections <<< "mysql-server mysql-server/root_password password ${ROOT_DBPASS}"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${ROOT_DBPASS}"
apt-get install -y mariadb-server

mysql -uroot -p${ROOT_DBPASS} -e "CREATE DATABASE reviewdb;"
mysql -uroot -p${ROOT_DBPASS} -e "GRANT ALL PRIVILEGES ON reviewdb.* TO 'gerrit'@'localhost' IDENTIFIED BY '${GERRIT_DBPASS}';";

# 4. Initialize the Site
useradd gerrit
echo "gerrit:${GERRIT_DBPASS}"| chpasswd
mkdir -p ${deployment_folder}/etc/
cat <<EOL > ${deployment_folder}/etc/gerrit.config
[gerrit]
        basePath = localhost
        canonicalWebUrl = http://${HOSTNAME}
[database]
        type = mysql
        hostname = localhost
        database = reviewdb
        username = gerrit
        password = ${GERRIT_DBPASS}
[index]
        type = LUCENE
[auth]
        type = DEVELOPMENT_BECOME_ANY_ACCOUNT
[receive]
        enableSignedPush = true
[sendemail]
        smtpServer = localhost
[container]
        user = root
        javaHome = /usr/lib/jvm/java-8-oracle/jre
[sshd]
        listenAddress = *:29418
[httpd]
        listenUrl = proxy-http://*:8080/
[cache]
        directory = cache
EOL

apt-get install -y gitweb

java -jar gerrit-${gerrit_version}.war init -d ${deployment_folder} --batch
# The second time downloads bcpkix jar
java -jar gerrit-${gerrit_version}.war init -d ${deployment_folder} --batch
java -jar gerrit-${gerrit_version}.war reindex -d ${deployment_folder}

ln -snf  ${deployment_folder}/bin/gerrit.sh /etc/init.d/gerrit
ln -snf /etc/init.d/gerrit /etc/rc3.d/S90gerrit

cat <<EOL > /etc/default/gerritcodereview
GERRIT_SITE=${deployment_folder}
EOL

service gerrit start

a2enmod proxy
a2enmod proxy_http

cat <<EOL > /etc/apache2/sites-available/000-default.conf
<VirtualHost *:80>
    ProxyPreserveHost On

    <Location />
        ProxyPass http://0.0.0.0:8080/
        Order allow,deny
        Allow from all
    </Location>
</VirtualHost>
EOL
service apache2 restart
