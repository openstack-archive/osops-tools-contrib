# LAMPstack Terraform deployments

## Status

This will install a 3 node lampstack by defulat. Two nodes will be used as
web servers and one node will be used as database node.

Once the script finishes, a set of URL will be displayed at the end for
verification.

## Requirements

- [Install Terraform](https://www.terraform.io/intro/getting-started/install.html)
- Make sure there is an Ubuntu image available on your cloud.

## Terraform

Terraform will be used to provision all of the OpenStack resources required to
LAMP stack and all required software.

### Prep

#### Deal with ssh keys for Openstack Authentication

Ensure your local ssh-agent is running and your ssh key has been added.
This step is required by the terraform provisioner. Otherwise, you will have
to use a key pair without passphrase.

```
$ eval $(ssh-agent -s)
$ ssh-add ~/.ssh/id_rsa

```

#### General Openstack Settings

Terraform OpenStack provider requires few environment variables to be set
before you can run the scripts. In general, you can simply export OS
environment varialbes like the following:

```
export OS_REGION_NAME=RegionOne
export OS_PROJECT_NAME=demo
export OS_IDENTITY_API_VERSION=3
export OS_PASSWORD=secret
export OS_DOMAIN_NAME=default
export OS_USERNAME=demo
export OS_TENANT_NAME=demo
export OS_PROJECT_DOMAIN_NAME=default
export OS_AUTH_URL=http://9.30.217.9:5000/v3

```


You most likely will need to specify the name of your Ubuntu `glance` image,
flavor, lamp stack size (how many nodes in the stack), private and public
network names, and keys. Here is the list of the default values defined in file
vars_openstack.tf.

```
image_name = "trusty 1404"
private_net = "internal"
public_net = "external"
flavor = "m1.medium"
public_key_path = "~/.ssh/id_rsa.pub"
stack_size = 3
```

You can change the settings in the file or you can simply set in environment
variables like the following:

```
export TF_VAR_image_name="trusty 1404"
export TF_VAR_private_net=Bluebox
export TF_VAR_public_net=internet
export TF_VAR_flavor="m1.small"
export TF_VAR_public_key_path="~/.ssh/id_rsa.pub"
export TF_VAR_stack_size=5

```

## Provision the LAMP stack

With all your OpenStack and TF vars set, you should be able to run
`terraform apply`.  But lets check with `terraform plan` that things look
correct first:


```
$ terraform plan
Refreshing Terraform state prior to plan...
...
...
+ openstack_networking_floatingip_v2.database
    address:   "<computed>"
    fixed_ip:  "<computed>"
    pool:      "internet"
    port_id:   "<computed>"
    region:    "RegionOne"
    tenant_id: "<computed>"


Plan: 8 to add, 0 to change, 0 to destroy.
```

If there is no errors showing,  we can go ahead and run

```
$ terraform apply
...
...
Outputs:

lampstack = Success!!!

Access service at the following URLs:
http://9.30.217.44
http://9.30.217.42

```

The above results show that the LAMP Stack actually provisioned correctly
and the LAMP application is up running and can be accessed by either of the
urls.


## Next Steps

### Check its up

Use the access urls to access the application. Since there are multiple web
server nodes, any of the urls should work.

```
$ curl http://9.30.217.20

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
Apply complete! Resources: 0 added, 0 changed, 8 destroyed.
```
