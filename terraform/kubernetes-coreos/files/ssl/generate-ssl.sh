#!/bin/bash

openssl genrsa -out files/ssl/ca-key.pem 2048
openssl req -x509 -new -nodes -key files/ssl/ca-key.pem -days 10000 -out files/ssl/ca.pem -subj '/CN=kubernetes-ca'
openssl genrsa -out files/ssl/admin-key.pem 2048
openssl req -new -key files/ssl/admin-key.pem -out files/ssl/admin.csr -subj '/CN=kubernetes-admin' -config files/ssl/openssl.cnf
openssl x509 -req -in files/ssl/admin.csr -CA files/ssl/ca.pem -CAkey files/ssl/ca-key.pem -CAcreateserial -out files/ssl/admin.pem -days 365 -extfile files/ssl/openssl.cnf
