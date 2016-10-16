#cloud-config

ssh_pwauth: true

users:
  - name: cicd
    passwd: $6$rounds=4096$DWIvD0b83l1wOVo$3Ww47Krh0JkgohulOJbr4W7WcvQuzlapHd0/qfjEmGvrA1YHjxmhS.Up6B/WV1/b5Yc5J7kvvPFvIbcqpMHII/
    lock_passwd: False
    sudo: ["ALL=(ALL) NOPASSWD:ALL\nDefaults:stack !requiretty"]
    shell: /bin/bash

runcmd:
  - wget https://raw.githubusercontent.com/electrocucaracha/terraform-cicd/master/redmine/postinstall_web.sh
  - chmod 755 postinstall_web.sh
  - bash postinstall_web.sh ${version} ${redmine_db_ip} ${redmine_db_password}
