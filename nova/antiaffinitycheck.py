#!/usr/bin/env python
""" Utility to check validity of anti-affinity rules """

import os
import sys
import argparse
from collections import defaultdict, Counter
from keystoneclient import session
from keystoneclient.auth.identity import v2
from keystoneclient.v2_0 import client as ksclient
from novaclient import client as nclient
import prettytable

def get_credentials():
    """ Build dictionary of Keystone credentials from environment """
    keystone_credentials = {}
    keystone_credentials['auth_url'] = os.environ['OS_AUTH_URL']
    keystone_credentials['username'] = os.environ['OS_USERNAME']
    keystone_credentials['password'] = os.environ['OS_PASSWORD']
    keystone_credentials['tenant_name'] = os.environ['OS_TENANT_NAME']
    return keystone_credentials

def get_args():
    """ Get commandline arguments """
    parser = argparse.ArgumentParser(description='Nova Server Group anti-affinity rule checker')
    parser.add_argument('--check', type=str, help='Validate the specified Server Group')
    parser.add_argument('--list', type=str, help='List instances and their hypervisors for a given Server Group')
    return parser.parse_args()

def get_server(serverid):
    """ Return Server object """
    return nova.servers.get(serverid)

def get_group_members(server_group_id):
    """ Return list of instance UUIDs present in a Server Group """
    server_group = nova.server_groups.get(server_group_id)
    if 'anti-affinity' in server_group.policies:
        return server_group.members
    else:
        return False

def create_table(fields):
    """ Boilerplate for PrettyTable """
    table = prettytable.PrettyTable(fields, caching=False)
    table.align = 'l'
    return table

def print_group_members(server_group_id):
    """ Print a table detailing Server Group instances and their hypervisors """
    group_members = get_group_members(server_group_id)
    if group_members:
        table = create_table(['Instance ID', 'Instance', 'Hypervisor'])
        for server in get_group_members(server_group_id):
            instance = get_server(server)
            hypervisor = getattr(instance, 'OS-EXT-SRV-ATTR:hypervisor_hostname'.split('.')[0])
            table.add_row([instance.id, instance.name, hypervisor])
        print table
    else:
        print "Server Group", server_group_id, "empty or does not have an anti-affinity policy set."

def print_group_duplicates(server_group_id):
    """ Evaluate whether any instances in a SG have been scheduled to the same hypervisor """
    group_members = get_group_members(server_group_id)
    if group_members:
        hypervisors = []
        instances = defaultdict(list)
        for instance in get_group_members(server_group_id):
            i = get_server(instance)
            hypervisor = getattr(i, 'OS-EXT-SRV-ATTR:hypervisor_hostname')
            instances[instance].append(i.name)
            instances[instance].append(hypervisor)
            hypervisors.append(hypervisor)
        dupes = [k for k, v in Counter(hypervisors).items() if v > 1]
        if dupes:
            print "Anti-affinity rules violated in Server Group:", server_group_id
            table = create_table(['Instance ID', 'Instance', 'Hypervisor'])
            [table.add_row([instance_id, instance_name, hypervisor])
             for instance_id, [instance_name, hypervisor] in instances.items()
             if hypervisor in dupes]
            print table
        else:
            print "No anti-affinity rules violated for Server Group:", server_group_id
    else:
        print "Server Group", server_group_id, "empty or does not have an anti-affinity policy set."

if __name__ == '__main__':
    credentials = get_credentials()
    keystone = ksclient.Client(**credentials)
    auth = v2.Password(**credentials)
    sess = session.Session(auth=auth)
    nova = nclient.Client(2, session=sess)
    args = get_args()
    group = sys.argv[2]
    if args.check:
        print_group_duplicates(group)
    if args.list:
        print_group_members(group)
