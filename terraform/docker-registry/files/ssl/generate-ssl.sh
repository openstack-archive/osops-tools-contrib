#!/bin/bash

openssl genrsa -out files/ssl/ca-key.pem 2048
openssl req -x509 -new -nodes -key files/ssl/ca-key.pem -days 10000 -out files/ssl/ca.pem -subj '/CN=registry-ca'
