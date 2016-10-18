# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|
  config.vm.box = "sputnik13/trusty64"

  config.vm.define :redmine_db do |redmine_db|
    redmine_db.vm.hostname = 'redmine-db'
    redmine_db.vm.network :private_network, ip: '192.168.50.2'
    redmine_db.vm.provider "virtualbox" do |v|
      v.customize ["modifyvm", :id, "--memory", 1 * 1024]
    end
    redmine_db.vm.provision 'shell' do |s|
      s.path = 'redmine/postinstall_db.sh'
      s.args = ['root_password', 'redmine_password']
    end
  end
  config.vm.define :redmine_web do |redmine_web|
    redmine_web.vm.hostname = 'redmine'
    redmine_web.vm.network :private_network, ip: '192.168.50.3'
    redmine_web.vm.provider "virtualbox" do |v|
      v.customize ["modifyvm", :id, "--memory", 2 * 1024]
    end
    redmine_web.vm.provision 'shell' do |s|
      s.path = 'redmine/postinstall_web.sh'
      s.args = ['3.3.0', '192.168.50.2', 'redmine_password']
    end
  end
  config.vm.define :gerrit do |gerrit|
    gerrit.vm.hostname = "gerrit"
    gerrit.vm.network :private_network, ip: '192.168.50.5'
    gerrit.vm.provider "virtualbox" do |v| 
      v.customize ["modifyvm", :id, "--memory", 1 * 1024]
    end 
    gerrit.vm.provision 'shell' do |s| 
      s.path = 'gerrit/postinstall.sh'
      s.args = ['127.0.0.1']
    end
  end 
  config.vm.define :jenkins do |jenkins|
    jenkins.vm.hostname = "jenkins"
    jenkins.vm.network :private_network, ip: '192.168.50.6'
    jenkins.vm.provider "virtualbox" do |v| 
      v.customize ["modifyvm", :id, "--memory", 1 * 1024]
    end 
    jenkins.vm.provision 'shell' do |s| 
      s.path = 'jenkins/postinstall.sh'
      s.args = ['192.168.50.3', '3.3.0', '192.168.50.5']
    end
  end
end
