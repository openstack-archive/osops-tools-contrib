#!/bin/bash

openssl genrsa -out files/ssl/ca-key.pem 2048

openssl req -x509 -new -nodes -key files/ssl/ca-key.pem -days 10000 -out files/ssl/ca.pem -subj '/CN=docker-CA'

openssl genrsa -out files/ssl/key.pem 2048

openssl req -new -key files/ssl/key.pem -out files/ssl/cert.csr -subj '/CN=docker-client' -config files/ssl/openssl.cnf

openssl x509 -req -in files/ssl/cert.csr -CA files/ssl/ca.pem -CAkey files/ssl/ca-key.pem \
  -CAcreateserial -out files/ssl/cert.pem -days 365 -extensions v3_req -extfile files/ssl/openssl.cnf
