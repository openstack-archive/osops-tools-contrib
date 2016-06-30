#!/usr/bin/env python
# pylint: disable=import-error
""" Utility to check validity of anti-affinity rules """

import os
import argparse
import json
from collections import Counter
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

class NovaConnect(object):
    """
    Base Nova connection class
    """
    def __init__(self, args):

        credentials = get_credentials()
        ksclient.Client(**credentials)
        auth = v2.Password(**credentials)
        sess = session.Session(auth=auth)
        self.nova = nclient.Client(2, session=sess)
        self.json = args.json

    def get_server(self, serverid):
        """
        Return Server object
        """
        return self.nova.servers.get(serverid)

    def get_all(self):
        """
        Get a list of all Server Groups
        """
        server_groups = self.nova.server_groups.list(all_projects=True)
        return server_groups

    def get_group_members(self, server_group_id):
        """
        Return list of instance UUIDs present in a Server Group
        """
        server_group = self.nova.server_groups.get(server_group_id)
        if 'anti-affinity' in server_group.policies:
            return server_group.members
        else:
            return False

    def get_hypervisors(self, uid_list):
        """
        Return a dict with hypervisors and names given a list of server uids
        """
        ret = []
        for uid in uid_list:
            instance = self.get_server(uid)
            hypervisor = getattr(instance,
                                 'OS-EXT-SRV-ATTR:hypervisor_hostname'
                                 .split('.')[0])
            ret.append({'id':uid,
                        'name':instance.name,
                        'hypervisor':hypervisor})
        return ret

    def get_group_detail(self, server_group_id):
        """
        Output detail on Server Group instances and their hypervisors
        """
        group_members = self.get_group_members(server_group_id)
        if group_members:
            output = self.get_hypervisors(group_members)
            return output
        else:
            return False

    def test_group_duplicates(self, server_group_id):
        """
        Evaluate whether any instances in a SG
        have been scheduled to the same hypervisor
        """
        group_members = self.get_group_members(server_group_id)
        if group_members:
            hypervisors = []
            instances = self.get_hypervisors(group_members)
            for instance in instances:
                instance['server_group_id'] = server_group_id
                hypervisors.append(instance['hypervisor'])
            dupes = [k for k, v in Counter(hypervisors).items() if v > 1]
            if dupes:
                instance_dupes = [instance for instance in instances
                                  if instance['hypervisor'] in dupes]
                return instance_dupes
            else:
                return False
        else:
            return False

    def check_all(self):
        """
        Check all server groups for violations
        """
        groups = self.get_all()
        merged_output = []
        for group in groups:
            output = self.test_group_duplicates(group.id)
            if output and self.json:
                merged_output += output
            elif output and not self.json:
                print "Anti-affinity rules violated in Server Group:",\
                            group.id
                print_table(output)
        if self.json and merged_output:
            print json.dumps(merged_output)

def create_table(fields):
    """
    Boilerplate for PrettyTable
    """
    table = prettytable.PrettyTable(fields, caching=False)
    table.align = 'l'
    return table

def print_table(output):
    """
    Print out a table of instances
    """
    table = create_table(['Instance ID', 'Instance Name', 'Hypervisor'])
    for instance in output:
        table.add_row([instance['id'],
                       instance['name'],
                       instance['hypervisor']])
    print table

def get_args():
    """
    Get commandline arguments
    """
    parser = argparse.ArgumentParser(description='Nova Server Group \
                                            anti-affinity rule checker')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--check', type=str,
                       help='Validate the specified Server Group')
    group.add_argument('--list', type=str,
                       help='List instances and their hypervisors \
                               for a given Server Group')
    group.add_argument('--all', action='store_true',
                       help='Check all server groups')
    parser.add_argument('--json', action='store_true', help='Output JSON')
    return parser.parse_args()

def main():
    """
    Main script
    """
    args = get_args()
    nova_connect = NovaConnect(args)
    if args.check:
        output = nova_connect.test_group_duplicates(args.check)
        if output and args.json:
            print json.dumps(output)
        elif output and not args.json:
            print "Anti-affinity rules violated in Server Group:",\
                            args.check
            print_table(output)
        elif not output and not args.json:
            print "No anti-affinity rules \
                    violated for Server Group:", args.check
    if args.list:
        output = nova_connect.get_group_detail(args.list)
        if output and args.json:
            print json.dumps(output)
        elif output and not args.json:
            print_table(output)
        elif not output and not args.json:
            print "Server Group", args.list,\
                "empty or does not have an anti-affinity policy set."
    if args.all:
        nova_connect.check_all()

if __name__ == '__main__':
    main()
