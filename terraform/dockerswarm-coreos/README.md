# Docker Swarm on Openstack with Terraform

Provision a Docker Swarm cluster with [Terraform](https://www.terraform.io) on Openstack.

## Status

This will install a fully HA docker swarm cluster on an Openstack Cloud. It is tested on a OpenStack Cloud provided by [BlueBox](https://www.blueboxcloud.com/) and should work on most modern installs of OpenStack that support the basic services.

It also supports overlay networks using the `docker network` command, see documentation below.


## Requirements

- [Install Terraform](https://www.terraform.io/intro/getting-started/install.html)
- Upload a CoreOS image to glance and remember the image name.

## Terraform

Terraform will be used to provision all of the OpenStack resources required to run Docker Swarm.   It is also used to deploy and provision the software requirements.

### Prep

#### Openstack Authentication

Ensure your local ssh-agent is running and your ssh key has been added. This step is required by the terraform provisioner.

```
$ eval $(ssh-agent -s)
$ ssh-add ~/.ssh/id_rsa
```

Ensure that you have your Openstack credentials loaded into Terraform environment variables. Likely via a command similar to:

```
$ source ~/.stackrc
$ export TF_VAR_username=${OS_USERNAME} 
$ export TF_VAR_password=${OS_PASSWORD}
$ export TF_VAR_tenant=${OS_TENANT_NAME}
$ export TF_VAR_auth_url=${OS_AUTH_URL}

```

#### General Openstack Settings

By default security_groups will allow certain traffic from `0.0.0.0/0`.  If you want to restrict it to a specific network you can set the terraform variable `whitelist_network`.  I like to set it to only allow my current IP:

```
$ export TF_VAR_whitelist_network=$(curl -s icanhazip.com)/32
```

You also want to specify the name of your CoreOS `glance` image as well as flavor,networks, and keys.  Since these do not change often I like to add them to `terraform.tfvars`:

```
image_name = "coreos-alpha-884-0-0"
network_name = "internal"
floatingip_pool = "external"
flavor = "m1.medium"
public_key_path = "~/.ssh/id_rsa.pub"
```

_Remove the `*.tfvars` line from `.gitignore` if you wish to save this file into source control_

see `vars-openstack.tf` for the full list of variables you can set.

#### Docker Swarm Settings

You can alter the number of instances to be built and added to the cluster by modifying the `cluster_size` variable (default is 3).

If you have a FQDN you plan at pointing at one of more of the swarm-manager hosts you can set it via the `fqdn` variable.

Terraform will attempt to run `openssl` commands to create a CA and server/client certificates used to secure the docker/swarm endpoints.  If you do not have `openssl` on your local machine or want to re-use existing CA / Client certificates you can set the TF variable `generate_ssl` to `0`.  The certificates are created in `files/ssl`.

see `vars-swarm.tf` for the full list of variables you can set.

#### CoreOS Settings

Terraform will attempt to generate an etcd discovery token by running `curl` against the etcd discovery service.  If do not have `curl` or do not wish to generate a new discovery url you can set `generate_discovery_url` to `0` and create a file `templates/discovery_url` which contains the discovery url you wish to use.

## Provision the Docker Swarm

With all your TF vars set you should be able to run `terraform apply` but lets check with `terraform plan` that things look correct first:


```
$ terraform plan
Refreshing Terraform state prior to plan...
...
...
+ template_file.discovery_url
    rendered: "" => "<computed>"
    template: "" => "templates/discovery_url"

Plan: 14 to add, 0 to change, 0 to destroy.
```

With no errors showing here we can go ahead and run

```
$ terraform apply
...
...
Apply complete! Resources: 14 added, 0 changed, 0 destroyed.

The state of your infrastructure has been saved to the path
below. This state is required to modify and destroy your
infrastructure, so keep it safe. To inspect the complete state
use the `terraform show` command.

State path: terraform.tfstate

Outputs:

  swarm_cluster = 
Environment Variables for accessing Docker Swarm via floating IP of first host:
export DOCKER_HOST=tcp://x.x.x.x:2375
export DOCKER_TLS_VERIFY=1
export DOCKER_CERT_PATH=/home/bacon/development/personal/terraform-dockerswarm-coreos/files/ssl
```

_the final output uses the floating IP of the first Host. You could point at any of the hosts, or use a FQDN with round robin DNS pointing at all the hosts.  I avoided using neutron's load balancing service as it is not yet standard on OpenStack installs._

## Next Steps

### Check its up

copy and paste the above output into your shell and attempt to run `docker info`:

```
$ export DOCKER_HOST=tcp://x.x.x.x:2375
$ export DOCKER_TLS_VERIFY=1
$ export DOCKER_CERT_PATH=/home/bacon/development/personal/terraform-dockerswarm-coreos/files/ssl

$ docker info
Containers: 6
Images: 6
Engine Version: 
Role: primary
Strategy: spread
Filters: health, port, dependency, affinity, constraint
Nodes: 3
 swarm-testing-0.novalocal: 10.230.7.171:2376
  └ Status: Healthy
  └ Containers: 2
  └ Reserved CPUs: 0 / 2
  └ Reserved Memory: 0 B / 4.057 GiB
  └ Labels: executiondriver=native-0.2, kernelversion=4.3.0-coreos, operatingsystem=CoreOS 884.0.0, storagedriver=overlay
 swarm-testing-1.novalocal: 10.230.7.172:2376
  └ Status: Healthy
  └ Containers: 2
  └ Reserved CPUs: 0 / 2
  └ Reserved Memory: 0 B / 4.057 GiB
  └ Labels: executiondriver=native-0.2, kernelversion=4.3.0-coreos, operatingsystem=CoreOS 884.0.0, storagedriver=overlay
 swarm-testing-2.novalocal: 10.230.7.173:2376
  └ Status: Healthy
  └ Containers: 2
  └ Reserved CPUs: 0 / 2
  └ Reserved Memory: 0 B / 4.057 GiB
  └ Labels: executiondriver=native-0.2, kernelversion=4.3.0-coreos, operatingsystem=CoreOS 884.0.0, storagedriver=overlay
CPUs: 6
Total Memory: 12.17 GiB
Name: swarm-testing-0.novalocal
```

### Create an overlay network and run a container

Create a network overlay called `my-net`

```
$ docker network create --driver overlay my-net
ecfefdff938f506b09c5ea5b505ee8ace0ee7297d9d617d06b9bbaac5bf10fea
$ docker network ls
NETWORK ID          NAME                               DRIVER
38338f0ec63a        swarm-testing-1.novalocal/host     host                
c41436d91f29        swarm-testing-0.novalocal/none     null                
e29c4451483f        swarm-testing-0.novalocal/bridge   bridge              
400130ea105b        swarm-testing-2.novalocal/none     null                
c8f15676b2a5        swarm-testing-2.novalocal/host     host                
493127ad6577        swarm-testing-2.novalocal/bridge   bridge              
74f862f34921        swarm-testing-1.novalocal/none     null                
ecfefdff938f        my-net                             overlay             
b09a38662087        swarm-testing-0.novalocal/host     host                
cfbcfbd7de02        swarm-testing-1.novalocal/bridge   bridge              
```

Run a container on the network on a specific host, then try to access it from another:

```
$ docker run -itd --name=web --net=my-net --env="constraint:node==swarm-testing-1.novalocal" nginx
53166b97adf2397403f00a2ffcdba635a7f08852c5fe4f452d6ca8c6f40bb80c
$ docker run -it --rm --net=my-net --env="constraint:node==swarm-testing-2.novalocal" busybox wget -O- http://web
Connecting to web (10.0.0.2:80)
<!DOCTYPE html>
<html>
...
...
<p><em>Thank you for using nginx.</em></p>
</body>
</html>

```

## Cleanup

Once you're done with it, don't forget to nuke the whole thing.

```
$ terraform destroy \
Do you really want to destroy?
  Terraform will delete all your managed infrastructure.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes
...
...
Apply complete! Resources: 0 added, 0 changed, 14 destroyed.
```
