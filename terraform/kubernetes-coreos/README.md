# Kubernetes on Openstack with Terraform

forked from [kelseyhightower/kubestack](https://github.com/kelseyhightower/kubestack)

Provision a Kubernetes cluster with [Terraform](https://www.terraform.io) on Openstack

## Status

Ready for testing. Over the next couple of weeks the repo should be generic enough for reuse with complete documentation.

Will install a single controller node and two compute nodes by default, can increase or decrease compute nodes using the Terraform variable `compute_count`.

## Prep

- [Install Terraform](https://www.terraform.io/intro/getting-started/install.html)
- Upload a Ubuntu Xenial or CentOS 7 image to glance.

## Terraform

Terraform will be used to declare and provision a Kubernetes cluster. By default it will be a single controller with a single compute node. You can add more nodes by adjusting the `compute_workers` variable.

The compute workers do not have a floating ip by default, this means to `ssh` to them you must use the controller node as a bastion and forward your SSH agent through.

### Prep

Ensure your local ssh-agent is running and your ssh key has been added. This step is required by the terraform provisioner.

```
$ eval $(ssh-agent -s); ssh-add ~/.ssh/id_rsa
```

Ensure that you have your Openstack credentials loaded into environment variables. Likely via a command similar to:

```
$ source ~/.stackrc
```

Edit the terraform.tfvars file to put the name of your ubuntu/centos image, OpenStack network names, etc.  If you use centos you will also have to change `ssh_user` to `centos`.


### Provision the Kubernetes Cluster

```
$ cd terraform
$ export MY_IP=$(curl -s icanhazip.com)
$ terraform plan \
      -var "username=$OS_USERNAME" \
      -var "password=$OS_PASSWORD" \
      -var "tenant=$OS_TENANT_NAME" \
      -var "auth_url=$OS_AUTH_URL" \
      -var "whitelist_network=${MY_IP}/32"
Refreshing Terraform state prior to plan...
...
...
+ template_file.discovery_url
    rendered: "" => "<computed>"
    template: "" => "templates/discovery_url"

Plan: 12 to add, 0 to change, 0 to destroy.

$ terraform apply \
      -var "username=$OS_USERNAME" \
      -var "password=$OS_PASSWORD" \
      -var "tenant=$OS_TENANT_NAME" \
      -var "auth_url=$OS_AUTH_URL" \
      -var "whitelist_network=${MY_IP}/32"
...
...
Apply complete! Resources: 16 added, 0 changed, 0 destroyed.

The state of your infrastructure has been saved to the path
below. This state is required to modify and destroy your
infrastructure, so keep it safe. To inspect the complete state
use the `terraform show` command.

State path: terraform.tfstate

Outputs:

  kubernetes-controller = $ ssh -A ubuntu@xx.xx.xx.xx
```

## Next Steps

### Check its up

```
$ ssh -A ubuntu@xx.xx.xx.xx

$ kubectl get nodes
NAME                            STATUS    AGE
kubestack-testing-compute0      Ready     8s
kubestack-testing-compute1      Ready     6s
kubestack-testing-controller0   Ready     2m

$ kubectl get pods --all-namespaces

```


### Run a demo application

```
$ git clone https://github.com/microservices-demo/microservices-demo
$ kubectl apply \
  -f microservices-demo/deploy/kubernetes/manifests/sock-shop-ns.yml \
  -f microservices-demo/deploy/kubernetes/manifests

$ kubectl describe svc front-end -n sock-shop
Name:     front-end
Namespace:    sock-shop
Labels:     name=front-end
Selector:   name=front-end
Type:     NodePort
IP:     100.79.5.35
Port:     <unset> 80/TCP
NodePort:   <unset> 30768/TCP
Endpoints:    10.36.0.3:8079
Session Affinity: None
```

once its online you can browse to it via the IP of the controller node, or via the endpoint if you're on the k8s controller.

```
$ curl -s 10.36.0.3:8079 | head
<!DOCTYPE html>
<html lang="en">

<head>

    <meta charset="utf-8">
    <meta name="robots" content="all,follow">
    <meta name="googlebot" content="index,follow,snippet,archive">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="description" content="WeaveSocks Demo App">
(23) Failed writing body

```

### Install The Dashboard Addon

```
$ kubectl create -f https://rawgit.com/kubernetes/dashboard/master/src/deploy/kubernetes-dashboard.yaml

$ kubectl describe svc kubernetes-dashboard -n kube-system
Name:     kubernetes-dashboard
Namespace:    kube-system
Labels:     app=kubernetes-dashboard
Selector:   app=kubernetes-dashboard
Type:     NodePort
IP:     100.64.81.128
Port:     <unset> 80/TCP
NodePort:   <unset> 31149/TCP
Endpoints:    10.44.0.7:9090
Session Affinity: None


```
You can now access the dashboard from your whitelisted IP at:
 ```http://<controller public ip>:<service port>```
The service port is supplied when you create the dashboard. In the example here, it was 32584.


### Destroy the cluster

Once you're done with it, don't forget to nuke the whole thing.

```
$ terraform destroy \
      -var "username=$OS_USERNAME" \
      -var "password=$OS_PASSWORD" \
      -var "tenant=$OS_TENANT_NAME" \
      -var "auth_url=$OS_AUTH_URL"
Do you really want to destroy?
  Terraform will delete all your managed infrastructure.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes
...
...
openstack_compute_secgroup_v2.kubernetes_controller: Destruction complete
openstack_compute_secgroup_v2.kubernetes_internal: Destruction complete

Apply complete! Resources: 0 added, 0 changed, 16 destroyed.
```
