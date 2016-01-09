# Docker Registry on Openstack with Terraform

Provision a Docker Registry with [Terraform](https://www.terraform.io) on Openstack.

## Status

This will install a Docker Registry on an Openstack Cloud. It is tested on a OpenStack Cloud provided by [BlueBox](https://www.blueboxcloud.com/) and should work on most modern installs of OpenStack.

By default the instance(s) will be booted up with only ephemeral storage. You can enable the swift backend with the terraform variable `docker_registry_storage_backend`.  You will also need to pass through swift credentials as described later.

The Docker Registry will use self signed certificates found in `files/ssl` which are regenerated every build ( see docs below on how to disable regeneration).  It will only allow connections from a client that uses this CA.  See docs below ( or the terraform output ) on how to use the CA on your local docker.

If you wish to use a different way to authenticate clients ( user, token,etc) modify the terraform variable `docker_registry_extra_args`.

By default it will start just a single server.  If you want more than one server running you will need to use the swift backend for the registry or do the following:

* Set up some sort of data replication for the `/opt/docker-registry/files` directory otherwise each server will have different content/
* set up load balancing, you could use round-robin-dns or a real load balancer.  Make sure you update the `fqdn` variable so that the SSL cert is created against the hostname you use.

## Requirements

- [Install Terraform](https://www.terraform.io/intro/getting-started/install.html)
- Upload a CoreOS image to glance and remember the image name [1].

[1] Any OS with docker installed should be able to be used here.  Update the terraform var `ssh_user` to be the user your OS expects.  If your image does not have docker installed you can update the terraform var `docker_install_command`.

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

#### Enabling Swift

You'll need to set the terraform variable `docker_registry_storage_backend` to `swift` and set the variables `swift_username`, `swift_password`, `swift_tenant`, `swift_auth_url`.

#### General Openstack Settings

By default security_groups will allow certain traffic from `0.0.0.0/0`.  If you want to restrict it to a specific network you can set the terraform variable `whitelist_network`.  I like to set it to only allow my current IP:

```
$ export TF_VAR_whitelist_network=$(curl -s icanhazip.com)/32
```

You may want to specify the name of your CoreOS `glance` image as well as flavor,networks, and keys if they do not match the defaults found in `variables.tf`.  Since these do not change often I like to add them to `terraform.tfvars`:

```
image = "coreos-alpha-884-0-0"
network_name = "internal"
floatingip_pool = "external"
flavor = "m1.medium"
public_key_path = "~/.ssh/id_rsa.pub"
```

_Remove the `*.tfvars` line from `.gitignore` if you wish to save this file into source control_

see `variables.tf` for the full list of variables you can set.

## Provision the Docker Registry

### Enable swift

If you want to use the swift backend, run this first, or set the Terraform variables another way:

_this re-uses your regular openstack credentials, you should actually use different credentials with less permissions._
```
$ export TF_VAR_docker_registry_storage_backend=swift
$ export TF_VAR_swift_username=${OS_USERNAME} 
$ export TF_VAR_swift_password=${OS_PASSWORD}
$ export TF_VAR_swift_tenant=${OS_TENANT_NAME}
$ export TF_VAR_swift_auth_url=${OS_AUTH_URL}
```

### Verify the Terraform configs

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

### Apply the Terraform configs

With no errors showing here we can go ahead and deploy.

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

  Do the following to use the registry = 

$ sudo mkdir -p /etc/docker/certs.d/X.X.X.X
$ sudo cp files/ssl/ca.pem /etc/docker/certs.d/X.X.X.X/ca.crt
```

## Next Steps

### Check its up

You can log into the host and access the registry directly:

```
$ ssh core@X.X.X.X
$ docker pull alpine
$ docker tag 127.0.0.1/alpine
$ docker push 127.0.0.1/alpine
74e49af2062e: Image already exists 
latest: digest: sha256:a96155be113bb2b4b82ebbc11cf1b511726c5b41617a70e0772f8180afc72fa5 size: 1369
```

You can configure your local docker to use the registration using the command provided in the terraform output ( you could also use the FQDN if you provided that in the terraform vars).

```
$ sudo cp files/ssl/ca.pem /etc/docker/certs.d/X.X.X.X/ca.crt
$ docker pull alpine
$ docker tag X.X.X.X/alpine
$ docker push X.X.X.X/alpine
74e49af2062e: Image already exists 
latest: digest: sha256:a96155be113bb2b4b82ebbc11cf1b511726c5b41617a70e0772f8180afc72fa5 size: 1369
```

## Cleanup

Once you're done with it, don't forget to nuke the whole thing.

```
$ sudo rm -rf /etc/docker/certs.d/X.X.X.X
$ terraform destroy \
Do you really want to destroy?
  Terraform will delete all your managed infrastructure.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes
...
...
Apply complete! Resources: 0 added, 0 changed, 14 destroyed.
```
