CI/CD for everyone else
=======================

This Terraform project pretends to provision all the OpenStack resources for a Development Infrastructure required for Applications that uses Continuous Integration and Continuos Delivery software cycle.

# Requirements:

- [Install Terraform] (https://www.terraform.io/intro/getting-started/install.html)
- Customize according to your OpenStack Provider

## General OpenStack settings

Terraform OpenStack provider needs environment variables to be set
before you can run the scripts. In general, you can simply export OS
environment variables like the following:

```
export OS_TENANT_NAME=osic-engineering
export OS_AUTH_URL=https://cloud1.osic.org:5000/v2.0
export OS_DOMAIN_NAME=Default
export OS_REGION_NAME=RegionOne
export OS_PASSWORD=secret
export OS_USERNAME=demo
```
Those values depend on the OpenStack Cloud provider.

## Steps for execution:

```
$ git clone https://github.com/electrocucaracha/terraform-cicd.git
$ cd terraform-cicd
$ terraform apply 
...
Apply complete! Resources: 13 added, 0 changed, 0 destroyed.
...
Outputs:

gerrit = http://10.0.0.1
jenkins = http://10.0.0.2
redmine = http://10.0.0.3
```

## Post-configuration

### Redmine Security Realm (authentication):

First you need to get consumer key/secret from Redmine OAuth Provider Plugin.

1. Log into your Redmine account.
2. Access to [YOUR_REDMINE_HOST]/oauth_clients
3. Click the **Register your application** link.
4. The system requests the following information:
   * **Name** is required. For example, input Jenkins
   * **Main Application URL** is required. For example, input your jenkins url.
   * **Callback URL** is required. For example, input [YOUR_JENKINS_HOST]/securityRealm/finishLogin
   * **Support URL** is not required.
5. Press **Register**.
   The system generates a key and a secret for you.
   Toggle the consumer name to see the generated Key and Secret value for your consumer.

Second, you need to configure your Jenkins.

1. Open Jenkins **Configure System** page.
2. Check **Enable security**.
3. Select **Redmine OAuth Plugin** in **Security Realm**.
4. Input your Redmine Url to **Redmine Url**.
5. Input your Consumer Key to **Client ID**.
6. Input your Consumer Secret to **Client Secret**.
7. Click **Save** button.

## Destroy:

    terraform destroy
