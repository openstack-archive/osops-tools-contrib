#!/bin/bash

version=$1
redmine_db_ip=$2
REDMINE_DBPASS=$3

export REDMINE_LANG=en
output_folder=/opt/redmine
redmine_folder=$output_folder/redmine-$version
bootstrap_plugin_version=0.2.4
jenkins_plugin_version=1.0.1
oauth_provider=0.0.5

# 0. Install dependencies
apt-get update -y
apt-get upgrade -y
apt-get install -y rubygems-integration ruby-dev libmysqlclient-dev build-essential libcurl4-openssl-dev

# 1. Redmine application
mkdir $output_folder
wget -O /tmp/redmine.tar.gz http://www.redmine.org/releases/redmine-$version.tar.gz
tar xzf /tmp/redmine.tar.gz -C $output_folder
cd $redmine_folder

# 3. Database connection configuration
cat <<EOL > config/database.yml
production:
  adapter: mysql2
  database: redmine
  host: ${redmine_db_ip}
  username: redmine
  password: "${REDMINE_DBPASS}"
  encoding: utf8
EOL

# 4. Dependencies installation
gem install bundler
bundle install --without development test rmagick

# 5. Session store secret generation
bundle exec rake generate_secret_token

# 6. Database schema objects creation
RAILS_ENV=production bundle exec rake db:migrate

# 7. Database default data set
RAILS_ENV=production bundle exec rake redmine:load_default_data

# 8. File system permissions
mkdir -p tmp tmp/pdf public/plugin_assets
useradd redmine
chown -R redmine:redmine files log tmp public/plugin_assets
chmod -R 755 files log tmp public/plugin_assets

# 9. Install Passenger packages
apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 561F9B9CAC40B2F7
apt-get install -y apt-transport-https ca-certificates
echo 'deb https://oss-binaries.phusionpassenger.com/apt/passenger trusty main' > /etc/apt/sources.list.d/passenger.list
apt-get update
apt-get install -y nginx-extras passenger
sed -i "s|# include /etc/nginx/passenger.conf;|include /etc/nginx/passenger.conf;|g" /etc/nginx/nginx.conf 

# 10. Configure Nginx
cat <<EOL > /etc/nginx/sites-available/redmine
server {
  listen  80;
  server_name www.redmine.me;
  root $redmine_folder/public;
  passenger_enabled on;
  client_max_body_size      10m; # Max attachemnt size
}
EOL
ln -s /etc/nginx/sites-available/redmine /etc/nginx/sites-enabled/redmine
rm /etc/nginx/sites-enabled/default

# Configure jenkins plugin and their dependencies
apt-get install -y git

cd ${redmine_folder}/plugins
git clone https://github.com/jbox-web/redmine_bootstrap_kit.git
pushd redmine_bootstrap_kit/
git checkout tags/${bootstrap_plugin_version}
popd

git clone https://github.com/jbox-web/redmine_jenkins.git
pushd redmine_jenkins/
git checkout tags/${jenkins_plugin_version}
popd

git clone https://github.com/suer/redmine_oauth_provider.git
pushd redmine_oauth_provider
git checkout tags/${oauth_provider}
popd

bundle install --without development test
bundle exec rake redmine:plugins:migrate RAILS_ENV=production

chown -R redmine:redmine ${redmine_folder}

service nginx restart
