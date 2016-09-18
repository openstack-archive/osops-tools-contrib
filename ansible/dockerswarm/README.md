# Docker Swarm Ansible deployments on OpenStack Cloud

## Status

This will install a 3 node lampstack. Once the script finishes, a set of
environment varialbes will be displayed, export these environment variable
then you can run docker commands against the swarm

## Requirements

- [Install Ansible](http://docs.ansible.com/ansible/intro_installation.html)
- [Install openstack shade] (http://docs.openstack.org/infra/shade/installation.html)
- Make sure there is an openstack coreos image available on your cloud.
- Clone this project into a directory.
- To run docker commands, you will need to install docker client. Following
  the following steps if you are using ubuntu to run the script, if you are
  using some other environment run the script, then the steps setting up
  docker client may be different::

    apt-get update
    apt-get -y install docker.io
    ln -sf /usr/bin/docker.io /usr/local/bin/docker  

## Ansible

Ansible and OpenStack Shade are used to provision all of the OpenStack
resources.

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
You may create one such file per cloud for your tests. The following is an
example::

    auth: {
      auth_url: "http://x.x.x.x:5000/v3",
      username: "demo",
      password: "{{ password }}",
      domain_name: "default",
      project_name: "demo"
    }

    app_env: {
      image_name: "coreos",
      region_name: "",
      private_net_name: "",
      net_device: "eth0",
      flavor_name: "m1.small",
      swarm_version: "latest",
      swarm_size: 3,
      fqdn: "swarm.example.com",
      public_key_file: "/home/tong/.ssh/id_rsa.pub"
    }


The values of these variables should be provided by your cloud provider. When
use keystone 2.0 API, you will not need to setup domain name. If your account
only has more than one regions available, specify the region_name to be used.
If there is only one, you can leave it blank or use the correct name. If your
cloud does not expose tenant network, leave private_net_name blank as well.
However, if your cloud supports tenant network and you have more than one
tenant networks in your account, you will need to specify which tenant network
to be used, otherwise, the script will error out. To create a large docker
swarm, change the swarm_size to a large value like 20, the script will create
a docker swarm with 20 coreos nodes.


## Run the script

With your cloud environment set, you should be able to run the script::

    ansible-playbook -e "action=apply env=leap password=XXXXX" site.yml

The command will stand up the nodes using a cloud named leap (vars/leap.yml).
If you run the test against other cloud, you can create a new file use same
structure and specify that cloud attributes such as auth_url, etc. Then you
can simply replace work leap with that file name. Replace xxxxx with your
own cloud account password, you can also simply put your password in the
configuration file (vars/leap.yml in this case) and avoid to specify it from
the command line.

If everything goes well, it will accomplish the following::

    1. Provision 3 coreos nodes on your cloud
    2. Create security group
    3. Add security rules to allow ping, ssh, docker access
    4. Setup ssl keys, certificates
    5. Display a set of environment variables that you can use to run docker
       commands


## Next Steps

### Check its up

If there are no errors, you can export the environment variables shown by
the script at the end. Then you can start running docker commands, here are
few examples::

    docker info
    docker images
    docker pull ubuntu:vivid


## Cleanup

Once you're done with the swarm, don't forget to nuke the whole thing::

    ansible-playbook -e "action=destroy env=leap password=XXXXX" site.yml

The above command will destroy all the resources created by the script.
