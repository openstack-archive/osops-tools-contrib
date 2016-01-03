# Kubernetes on Openstack with Terraform

forked from [kelseyhightower/kubestack](https://github.com/kelseyhightower/kubestack)

Provision a Kubernetes cluster with [Terraform](https://www.terraform.io) on Openstack

## Status

Ready for testing. Over the next couple of weeks the repo should be generic enough for reuse with complete documentation.

Will install a single controller node and two compute nodes by default, can increase or decrease compute nodes using the Terraform variable `compute_count`.

## Prep

- [Install Terraform](https://www.terraform.io/intro/getting-started/install.html)
- Upload a CoreOS image to glance.

## Terraform

Terraform will be used to declare and provision a Kubernetes cluster. By default it will be a single controller with a single compute node. You can add more nodes by adjusting the `compute_workers` variable.

The compute workers (for now) do not have a floating ip, this means to `ssh` to them you must `ssh -A` to the controller node first.

### Prep

Ensure your local ssh-agent is running and your ssh key has been added. This step is required by the terraform provisioner.

```
$ eval $(ssh-agent -s)
$ ssh-add ~/.ssh/id_rsa
```

Ensure that you have your Openstack credentials loaded into environment variables. Likely via a command similar to:

```
$ source ~/.stackrc
```

### Provision the Kubernetes Cluster

If you wish to re-use previously generated SSL key/certs for CA and admin, simply add `-var "generate_ssl=0" \`.

It can take some time for the `kubernetes-api` to come online.  Do not be surprised if you see a series of failed `curl` commands, this is just a `terraform` provisioning script waiting until it can access the api before moving on.

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
Apply complete! Resources: 12 added, 0 changed, 0 destroyed.

The state of your infrastructure has been saved to the path
below. This state is required to modify and destroy your
infrastructure, so keep it safe. To inspect the complete state
use the `terraform show` command.

State path: terraform.tfstate

Outputs:

  kubernetes-controller = $ ssh -A core@xx.xx.xx.xx
```

## Next Steps

### Check its up

```
$ ssh -A core@xx.xx.xx.xx

$ kubectl config use-context kubernetes
switched to context "kubernetes".

$ kubectl config view
apiVersion: v1
clusters:
- cluster:
    insecure-skip-tls-verify: true
    server: https://127.0.0.1:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: admin
  name: kubernetes
current-context: kubernetes
kind: Config
preferences: {}
users:
- name: admin
  user:
    token: kubernetes

$ kubectl get nodes  
NAME          LABELS                               STATUS    AGE
10.230.7.23   kubernetes.io/hostname=10.230.7.23   Ready     5m
```


### Run a container

```
$ kubectl run my-nginx --image=nginx --replicas=1 --port=80
replicationcontroller "my-nginx" created

$ kubectl expose rc my-nginx --port=80 --type=LoadBalancer
service "my-nginx" exposed

$ kubectl get svc my-nginx
NAME       CLUSTER_IP      EXTERNAL_IP   PORT(S)   SELECTOR       AGE
my-nginx   10.200.43.104                 80/TCP    run=my-nginx   6s

$ kubectl get pods
NAME             READY     STATUS    RESTARTS   AGE
my-nginx-k1zoe   1/1       Running   0          1m

$ curl 10.200.43.104
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>


$ kubectl delete rc my-nginx
replicationcontroller "my-nginx" deleted

$ kubectl delete svc my-nginx
service "my-nginx" deleted
```

### Install some addons

```
$ kubectl create -f /etc/kubernetes/addons/kube-ui-rc.yaml \
    --namespace=kube-system
$ kubectl create -f /etc/kubernetes/addons/kube-ui-svc.yaml \
    --namespace=kube-system
$ kubectl create -f /etc/kubernetes/addons/kube-dns-rc.yaml \
    --namespace=kube-system
$ kubectl create -f /etc/kubernetes/addons/kube-dns-svc.yaml \
    --namespace=kube-system
```


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

Apply complete! Resources: 0 added, 0 changed, 12 destroyed.      
```
