#!/bin/bash

if which apt > /dev/null; then
  echo "==> Detected Ubuntu"
  echo "----> Installing Kubernetes apt repo"
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
  cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
  apt-get -yq update > /dev/null
  echo "----> Installing Kubernetes requirements"
  apt-get install -yq docker.io kubelet kubeadm kubectl kubernetes-cni > /dev/null
elif which yum > /dev/null; then
  echo "==> Detected CentOS/RHEL"
  echo "----> Installing Kubernetes apt repo"
  cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=http://yum.kubernetes.io/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
  echo "----> YOLO setenforce"
  setenforce 0

  yum install -y docker kubelet kubeadm kubectl kubernetes-cni > /dev/null
  systemctl enable docker && systemctl start docker
  systemctl enable kubelet && systemctl start kubelet
else
  echo "YOUR OPERATING SYSTEM IS NOT SUPPORTED"
  echo "MUST BE Ubuntu Xenial or Centos/Redhat 7"
  exit 1
fi
