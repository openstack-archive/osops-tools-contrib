# LAMPstack Ansible deployments on OpenStack Cloud

## Status

This will install a 4 node lampstack. The first node will be used as a load
balancer by using Haproxy. The second node will be a database node and two
nodes will be used as web servers. If it is desirable for more node, you
can simply increase the number of nodes in the configuration, all added nodes
will be used as web servers.

Once the script finishes, a URL will be displayed at the end for verification.

## Requirements

- [Install Ansible](http://docs.ansible.com/ansible/intro_installation.html)
- [Install openstack shade] (http://docs.openstack.org/infra/shade/installation.html)
- Make sure there is an Ubuntu cloud image available on your cloud.
- Clone this project into a directory.

## Ansible

Ansible and OpenStack Shade will be used to provision all of the OpenStack
resources required by LAMP stack.

### Prep

#### Deal with ssh keys for Openstack Authentication

If you do not have a ssh key, then you should create one by using a tool.
An example command to do that is provided below. Once you have a key pair,
ensure your local ssh-agent is running and your ssh key has been added.
This step is required. Not doing this, you will have to manually give
passphrase when script runs, and script can fail. If you really do not want
to deal with passphrase, you can create a key pair without passphrase::

    ssh-keygen -t rsa
    eval $(ssh-agent -s)
    ssh-add ~/.ssh/id_rsa

#### General Openstack Settings

Ansible's OpenStack cloud module is used to provision compute resources
against an OpenStack cloud. Before you run the script, the cloud environment
will have to be specified. Sample files have been provided in vars directory.
You may create one such file per cloud for your tests.

    auth: {
      auth_url: "http://x.x.x.x:5000/v3",
      username: "demo",
      password: "{{ password }}",
      domain_name: "default",
      project_name: "demo"
    }

    app_env: {
      image_name: "trusty 1404",
      private_net_name: "Bluebox",
      public_net_name: "internet",
      public_key_file: "/home/ubuntu/.ssh/id_rsa.pub",
      stack_size: 4,
      volume_size: 2,
      volume_point: "/dev/vdb",
      wp_theme: "https://downloads.wordpress.org/theme/iribbon.2.0.65.zip",
      wp_posts: "http://wpcandy.s3.amazonaws.com/resources/postsxml.zip"
    }


The values of these variables should be provided by your cloud provider. When
use keystone 2.0 API, you will not need to setup domain name.


## Provision the LAMP stack

With your cloud environment set, you should be able to run the script::

    ansible-playbook -e "action=apply env=leap password=XXXXX" site.yml

The command will stand up the nodes using a cloud named leap (vars/leap.yml).
If you run the test against other cloud, you can create a new file use same
structure and specify that cloud attributes such as auth_url, etc. Then you
can simply replace work leap with that file name. Replace xxxxx with your
own password.

If everything goes well, it will accomplish the following::

    1. Provision 4 nodes
    2. Create security group
    3. Add security rules to allow ping, ssh, mysql and nfs access
    4. Create a cinder volume
    5. Attach the cinder volume to database node for wordpress database and
       content
    6. Setup NFS on database node, so that web servers can share the cinder
       volume space, all wordpress content will be saved on cinder volume.
       This is to ensure that the multiple web servres will represent same
       content.
    7. Setup mysql to use the space provided by cinder volume
    8. Configure and initialize wordpress
    9. Install and activte a wordpress theme specified by configuration file
    10.Install wordpress importer plugin
    11.Import sample word press content
    12.Remove not needed floating IPs from servers which do not need them.


## Next Steps

### Check its up

If there are no errors, you can use the IP addresses of the webservers to
access wordpress. If this is the very first time, you will be asked to do
answer few questions. Once that is done, you will have a fully functional
wordpress running.

## Cleanup

Once you're done with it, don't forget to nuke the whole thing::

    ansible-playbook -e "action=destroy env=leap password=XXXXX" site.yml

The above command will destroy all the resources created.
