#!/usr/bin/python

__author__      = 'Matthew Fischer <matt@mattfischer.com>'
__copyright__   = 'Copyright 2015, Matthew Fischer'

# Copyright 2015 Matthew Fischer
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Given the FQDN of a hypervisor, this tool will pull a list of all
# VMs on the hypervisor along with contact info for all the customers.
# Additionally an email list, which is pasteable into a mail client
# is generated. This tool is designed to be used when a hypervisor
# dies or maintenance is pending to notify customers about an issue,
# either before or after it happens.
#
# It uses environment variables to talk to OpenStack. Source
# an openrc first.

from keystoneclient.v2_0 import client as keystone_client
from novaclient import client as nova_client
import argparse
import os
import sys

def build_user_dict(keystone):
    _users_hash = {}
    users = keystone.users.list()
    for user in users:
        _users_hash[user.id] = user
    return _users_hash


def main(host):
    keystone = keystone_client.Client(username=os.environ.get('OS_USERNAME'),
            password=os.environ.get('OS_PASSWORD'),
            tenant_name=os.environ.get('OS_TENANT_NAME'),
            region_name=os.environ.get('OS_REGION_NAME'),
            auth_url=os.environ.get('OS_AUTH_URL'))
    users_hash = build_user_dict(keystone)

    nova = nova_client.Client('2', os.environ.get('OS_USERNAME'),
            os.environ.get('OS_PASSWORD'),
            os.environ.get('OS_TENANT_NAME'),
            region_name=os.environ.get('OS_REGION_NAME'),
            auth_url=os.environ.get('OS_AUTH_URL'),
            service_type="compute")

    print "Generating Server List & Info for %s" % host
    print "--------------------------------------------------------------"
    vms = get_vms_for_host(host, nova)
    if len(vms) == 0:
        print "\nNo VMs found on %s" % host
        return 1
    unique_emails = []
    for vm in vms:
        print "%-45s: %-15s (%s)" % (vm.name, users_hash[vm.user_id].name, users_hash[vm.user_id].email)
        user_email = users_hash[vm.user_id].email
        if user_email and user_email not in unique_emails:
            unique_emails.append(user_email)
        
    print "\n--------------------------------------------------------------"
    print "Email List"
    print "--------------------------------------------------------------"
    print '; '.join(unique_emails)
        

def get_vms_for_host(host, nova):
    vms = []
    # unfortunately I can't get a VM list from a given host
    for server in nova.servers.list(search_opts={'all_tenants': 1}):
        if host == getattr(server, 'OS-EXT-SRV-ATTR:hypervisor_hostname'):
            vms.append(server)
    return vms

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True, help='FQDN required!')
    args = parser.parse_args()
    if not '.' in args.host:
        print "Please call with the FQDN of the host"
        sys.exit(1)
    main(args.host)
