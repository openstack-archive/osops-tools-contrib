# DEIS on Openstack with Terraform

Provision a DEIS cluster with [Terraform](https://www.terraform.io) on
Openstack.

## Status

This will install a DEIS cluster on an Openstack Cloud. It is tested on a
OpenStack Cloud provided by [BlueBox](https://www.blueboxcloud.com/) and
should work on most modern installs of OpenStack that support the basic
services.

## Requirements

- [Install Terraform](https://www.terraform.io/intro/getting-started/install.html)
- [Install DEIS CLI](http://docs.deis.io/en/latest/using_deis/install-client/)
- ]Upload a CoreOS](https://coreos.com/os/docs/latest/booting-on-openstack.html) image to glance and remember the image name.

## Terraform

Terraform will be used to provision all of the OpenStack resources required to
run Docker Swarm.   It is also used to deploy and provision the software
requirements.

### Prep

#### OpenStack

Ensure your OpenStack credentials are loaded in environment variables. This is
how I do it:

```
$ source ~/.stackrc
```

You will need two networks before installing, an internal network and 
an external (floating IP Pool) network. The internet network can be shared as
we use security groups to provide network segregation. Due to the many
differences between OpenStack installs the Terraform does not attempt to create
these for you.

By default Terraform will expect that your networks are called `internal` and
`external`. You can change this by altering the Terraform variables `network_name` and `floatingip_pool`.

You can also change the number of instances `cluster_size` (default `3`); the
path to your public key `public_key_path` (default `~/.ssh/id_rsa.pub`); and
the flavor `flavor` to use (default `m1.medium`).

All OpenStack resources will use the Terraform variable `cluster_name` (
default `example`) in their name to make it easier to track. For example the
first compute resource will be named `example-deis-1`.

#### Terraform

Ensure your local ssh-agent is running and your ssh key has been added. This
step is required by the terraform provisioner:

```
$ eval $(ssh-agent -s)
$ ssh-add ~/.ssh/id_rsa
```


Ensure that you have your Openstack credentials loaded into Terraform
environment variables. Likely via a command similar to:

```
$ export TF_VAR_username=${OS_USERNAME} 
$ export TF_VAR_password=${OS_PASSWORD}
$ export TF_VAR_tenant=${OS_TENANT_NAME}
$ export TF_VAR_auth_url=${OS_AUTH_URL}
```

Terraform expects an SSH keypair to exist `keys/deis` and `keys/deis.pub`
which it will upload to the instances so they can communicate with eachother
over SSH, if this keypair doesn't exist it will attempt to create them.

Terraform will attempt to fetch a _Discovery URL_ for etcd.  If you want to
provide your own write it to the text file `files/discovery_url` and set the
Terraform variable `generate_discovery_url` to `0`.

You can also change the version of DEIS to install by setting `deisctl_version`
and you can set `deis_domain` if you have a custom URL (otherwise it will use 
`.xip.io`).


# Provision a Deis Cluster on OpenStack

With all our variables set we can go ahead and provision our cluster adding any
extra variables you wish to pass through like this:

_The steps that install and start deis can take quite some time, be patient._

```
$ terraform apply \
      -var "image=coreos-alpha-884-0-0"
...
...
Apply complete! Resources: 12 added, 0 changed, 0 destroyed.

The state of your infrastructure has been saved to the path
below. This state is required to modify and destroy your
infrastructure, so keep it safe. To inspect the complete state
use the `terraform show` command.

State path: terraform.tfstate

Outputs:

  msg      = Your hosts are ready to go! Continue following the documentation to install and start Deis. Your hosts are: x.x.x.x, y.y.y.y, z.z.z.z
  register = Run the following to register your first [admin] user: $ deis register http://deis.x.x.x.x.xip.io

```

# Create first user and deploy a demonstration app:

Create admin user:

```
$ deis register http://deis.x.x.x.x.xip.io
username: admin
password: 
password (confirm): 
email: admin@example.com
Registered admin
upgrading.
Logged in as admin
```

Upload a SSH key:

```
$ deis keys:add ~/.ssh/id_rsa.pub
Uploading id_rsa.pub to deis... done
```

Deploy an example application:

```
$ git clone https://github.com/deis/example-python-flask.git
$ cd example-python-flask
$ deis create
Creating Application... o..done, created hungry-knapsack

$ git push deis master
Counting objects: 98, done.
Delta compression using up to 8 threads.
Compressing objects: 100% (88/88), done.
Writing objects: 100% (98/98), 22.55 KiB | 0 bytes/s, done.
Total 98 (delta 38), reused 0 (delta 0)
-----> Python app detected
-----> Installing runtime (python-2.7.10)
-----> Installing dependencies with pip
...
-----> Discovering process types
-----> Compiled slug size is 37M
-----> Building Docker image
remote: Sending build context to Docker daemon 38.33 MB
...
Step 1 : ENV GIT_SHA 774eded22b5bab907c89a29b100ccc7f2423b729
 ---> Running in 75274e449a86
 ---> 3ec06b68ed87
Removing intermediate container 75274e449a86
Successfully built 3ec06b68ed87
-----> Pushing image to private registry
-----> Launching... 
       done, hungry-knapsack:v2 deployed to Deis
       http://hungry-knapsack.x.x.x.x.xip.io
       To learn more, use `deis help` or visit http://deis.io
To ssh://git@deis.x.x.x.x.xip.io:2222/hungry-knapsack.git
 * [new branch]      master -> master

```

Test that it works:

```
$ curl http://hungry-knapsack.x.x.x.x.xip.io/
Powered by Deis
```

Scale it up:

```
$ deis scale web=3
Scaling processes... but first, coffee!
..o
=== hungry-knapsack Processes
--- web:
web.1 up (v2)
web.2 up (v2)
web.3 up (v2)
$ curl http://hungry-knapsack.x.x.x.x.xip.io/
Powered by Deis
```

Configure it:

```
$ deis config:set POWERED_BY=OpenStack
Creating config... ..o
done, v3
=== hungry-knapsack Config
POWERED_BY      OpenStack

$ curl http://hungry-knapsack.x.x.x.x.xip.io/
Powered by OpenStack
```

Destroy it:

```
$ deis destroy
 !    WARNING: Potentially Destructive Action
 !    This command will destroy the application: hungry-knapsack
 !    To proceed, type "hungry-knapsack" or re-run this command with --confirm=hungry-knapsack
> hungry-knapsack
Destroying hungry-knapsack...
done in 3s
Git remote deis removed
```

# clean up:

```
$ terraform destroy
Do you really want to destroy?
  Terraform will delete all your managed infrastructure.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes
...
...
Apply complete! Resources: 0 added, 0 changed, 12 destroyed.
```
