#!/usr/bin/env python
#
#  Copyright (c) 2016 SWITCH http://www.switch.ch
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.

# Author: Simon Leinen  <simon.leinen@switch.ch>
# Date: 2016-09-04

from __future__ import print_function
import sys
import os
import argparse
import re
import paramiko
import multiprocessing
sys.path.append('../lib')
import openstackapi


def get_environ(key, verbose=False):
    if key not in os.environ:
        print("ERROR:", key, "not defined in environment")
        sys.exit(1)
    if verbose:
        if 'password' in key.lower():
            key_value = '*' * len(os.environ[key])
        else:
            key_value = os.environ[key]
        print(u"{}: {}".format(key, key_value))
    return os.environ[key]


class LibvirtDomainInfo:
    def __init__(self, uuid):
        self.uuid = uuid
        self.info = {}

class HypervisorInfo:
    def __init__(self, hostname):
        self.hostname = hostname
        self.domains = {}
        self.errors = []
    def add_domain(self, dom):
        self.domains[dom.uuid] = dom

class ServerInfo:
    def __init__(self, nova_info):
        self.nova_info = nova_info


def collect_hypervisor_information(nova, verbose=False,
                                   remote_user=None,
                                   blindly_trust_host_keys=False,
                                   processes=None):
    """Collect domain information from libvirt hypervisors in a region

    Arguments:

    nova: nova_client instance for the region
    verbose: Whether to print messages about harmless actions, default: False
    remote_user: The user under which SSH tries to connect, default: None
    blindly_trust_host_keys: Allow MITM attacks, default: False

    This function enumerates the hypervisors for the region, connects
    to each over SSH, and retrieves information about the libvirt
    domains running on the respective machine.

    The results are returned as a dictionary that maps domain UUIDs -
    which should correspond to Nova instance UUIDs - to
    LibvirtDomainInfo objects which are populated using virsh dominfo.
    """
    hyp = {}
    hypervisors = nova.hypervisors.list(detailed=True)
    pool = multiprocessing.Pool(processes=processes)

    if hypervisors:
        mapped = pool.map(_get_hypervisor_info,
                          map(lambda h: {
                              'hostname': h.hypervisor_hostname,
                              'verbose': verbose,
                              'remote_user': remote_user,
                              'blindly_trust_host_keys': blindly_trust_host_keys,
                              },
                              hypervisors))
        pool.close()
        pool.join()
        for h in mapped:
            if h.errors:
                print(u"Error getting domain information from {}".
                      format(h.hostname))
                for err in h.errors:
                    print(u"  {}".format(err))
            hyp[h.hostname] = h
    return hyp

def _get_hypervisor_info(closure):
    return get_hypervisor_info(
        closure['hostname'],
        verbose                =closure['verbose'],
        remote_user            =closure['remote_user'],
        blindly_trust_host_keys=closure['blindly_trust_host_keys'],
    )

def get_hypervisor_info(hostname,
                        verbose=False,
                        remote_user=None,
                        blindly_trust_host_keys=False):
    """Get domain information from a single libvirt hypervisor

    The results are returned as a HypervisorInfo object.

    Arguments:

    hostname: Hypervisor hostname from Nova.hypervisors.list(detailed=True)
    verbose: Whether to print messages about harmless actions, default: False
    remote_user: The user under which SSH tries to connect, default: None
    blindly_trust_host_keys: Allow MITM attacks, default: False

    This function connects to the given hypervisor over SSH and
    retrieves information about the libvirt domains known there.
    """

    h = HypervisorInfo(hostname)
    ssh = paramiko.SSHClient()
    if blindly_trust_host_keys:
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    try:
        ssh.connect(h.hostname, username=remote_user)
        _, stdout, stderr = ssh.exec_command("virsh list --uuid --all")
        for line in stdout:
            uuid = line.rstrip()
            if uuid == '':
                pass
            else:
                if verbose:
                    print("Found virsh instance {} on {}".format(
                        uuid, h.hostname))
                dom = LibvirtDomainInfo(uuid)
                h.add_domain(dom)
        for uuid, dom in h.domains.iteritems():
            _, stdout, stderr = ssh.exec_command("virsh dominfo {}".format(uuid))
            dominfo = re.compile("^([^:]*):\s*(.*)$")
            for line in stdout:
                if line == "\n":
                    # Ignore stupid trailing empty line
                    pass
                else:
                    m = dominfo.match(line)
                    if m:
                        dom.info[m.group(1).lower()] = m.group(2)
                    else:
                        h.errors.append(u"Cannot understand line {} in virsh dominfo output".
                                        format(line))
    except paramiko.SSHException as e:
        h.errors.append(u"Error SSHing to {}:\n    {}".
                        format(h.hostname, e.message))
    except:
        h.errors.append(u"Unexpected error SSHing to {}:\n    {}".
                        format(h.hostname, sys.exc_info()[0]))
    ssh.close()
    return h

def collect_server_information(nova, verbose=False):
    """Collect instance information from Nova in a region

    Arguments:

    nova: nova_client instance for the region
    verbose: Whether to print messages about harmless actions, default: False

    This function enumerates the instances from the Nova compute
    service in a region.

    The results are returned as a dictionary that maps domain UUIDs -
    which should correspond to Nova instance UUIDs - to ServerInfo
    objects which contain server detail information.
    """
    srv = {}

    servers = nova.servers.list(
        detailed=True,
        search_opts={'all_tenants': True})

    while servers:
        last_server = None
        for server in servers:
            last_server_id = server.id
            s = ServerInfo(server)
            srv[server.id] = s
            if verbose:
                print(u"Found server {} on hypervisor {} ({})".format(
                    server.id,
                    server._info['OS-EXT-SRV-ATTR:hypervisor_hostname'],
                    server.status,
                ))
        servers = nova.servers.list(
            detailed=True,
            marker=last_server_id,
            search_opts={'all_tenants': True})
    return srv

def report_server_hypervisor_inconsistencies(srv, hyp, verbose=False, note_incomplete=True):
    """Detect and report discrepancies between Nova and hypervisor views

    Arguments:

    srv: Dictionary of Nova instances as returned by collect_server_information()
    hyp: Dictionary of Hypervisor information as returned by collect_hypervisor_information()
    verbose: Whether to print messages about harmless actions, default: False
    note_incomplete: Whether to report instances without hypervisors, default: True

    The following types of discrepancies are detected and reported:

    * an instance exists in Nova, but is not on any hypervisor
    * an instance exists on a hypervisor, but is unknown to Nova
    * an instance exists on a hypervisor, but Nova thinks it should be on a different one
    * an instance has incompatible states between Nova and the hypervisor
    """
    state_mapping = {
        'ACTIVE':    'running',
        'SUSPENDED': 'shut off',
        'SHUTOFF':   'shut off',
        'PAUSED':    'paused',
    }
    for uuid, s in srv.iteritems():
        nova_status = s.nova_info.status
        hypervisor_name = s.nova_info._info['OS-EXT-SRV-ATTR:hypervisor_hostname']
        if hypervisor_name is None:
            if note_incomplete:
                print(u"Instance {} (Nova status {}) has no hypervisor".
                      format(uuid, nova_status))
        elif hypervisor_name not in hyp:
            print(u"Instance {} (Nova status {}) on unknown hypervisor {}".
                  format(uuid, nova_status, hypervisor_name))
        else:
            h = hyp[hypervisor_name]
            if uuid in h.domains:
                dom = h.domains[uuid]
                dom_state = dom.info['state']
                if verbose:
                    print(u"Instance {} (Nova state {}) hypervisor {} state {}".
                          format(uuid, nova_status, hypervisor_name, dom_state))
                if nova_status in state_mapping \
                   and dom_state == state_mapping[nova_status]:
                    pass
                else:
                    print((u"Possible inconsistency: Instance {} (Nova status {})\n"
                           +u"  On hypervisor {}, it has state {}").
                          format(uuid, nova_status,
                                 hypervisor_name, dom_state))
            elif h.errors:
                # It's not worth complaining.  The problem is that
                # there were errors trying to get domain information
                # from the hypervisor, and that has been signaled
                # already.
                pass
            else:
                print(u"Hypervisor {} should know about {}, but doesn't".
                      format(hypervisor_name, uuid))
    for hypervisor_name, h in hyp.iteritems():
        for uuid, s in h.domains.iteritems():
            if not uuid in srv:
                print(u"Hypervisor {} contains unknown instance {}".
                      format(hypervisor_name, uuid))
            else:
                nova_srv = srv[uuid]
                nova_status = nova_srv.nova_info.status
                nova_hyp_name = nova_srv.nova_info._info['OS-EXT-SRV-ATTR:hypervisor_hostname']
                if nova_hyp_name == hypervisor_name:
                    pass
                elif nova_hyp_name not in hyp:
                    print((u"Instance {} (Nova status {}):\n"
                           +u"  Found on hypervisor {} (state: {})\n"
                           +u"  Should be running on {}, which is not known.").
                          format(uuid, nova_status,
                                 hypervisor_name, s.info['state'],
                                 nova_hyp_name))
                else:
                    nova_hyp = hyp[nova_hyp_name]
                    if uuid not in nova_hyp.domains:
                        print((u"Instance {} (Nova status {}):\n"
                               +u"  Found on hypervisor {} (state: {})\n"
                               +u"  Should be running on {}, but unknown there.").
                              format(uuid, nova_status,
                                     hypervisor_name, s.info['state'],
                                     nova_hyp_name))
                    else:
                        nova_s = nova_hyp.domains[uuid]
                        print((u"Instance {} (Nova status {}):\n"
                               +u"  Found on hypervisor {} (state: {})\n"
                               +u"  Should be running on {}, and it is (state: {}).").
                              format(uuid, nova_status,
                                     hypervisor_name, s.info['state'],
                                     nova_hyp_name, nova_s.info['state']))

def main():
    """Check for state inconsistencies between Nova DB and hypervisors

    Go through nova-compute hosts, and check if the status of
    VMs running there corresponds to the state of the Nova database.

    Only supports libvirt hypervisors.

    Requires SSH access to all hypervisor hosts.  The remote user on
    the hypervisor must have sufficient privileges to run "virsh".
    """
    parser = argparse.ArgumentParser(
        description="Check for inconsistent state between Nova DB and hypervisors")
    parser.add_argument(
        '-a', '--all-regions', help='query all regions', action='store_true')
    parser.add_argument(
        '-l', '--remote-user', type=str,
        help='SSH remote username for connecting to hypervisors')
    parser.add_argument(
        '--no-note-incomplete', help='Don\'t report incomplete instances', action='store_true')
    parser.add_argument(
        '-b', '--blindly-trust-host-keys', help='Accept all SSH host keys. This enables man-in-the-middle attacks!', action='store_true')
    parser.add_argument(
        '-p', '--processes', type=int, default=20,
        help='Number of parallel processes connecting to hypervisors')
    parser.add_argument('-v', '--verbose', help='verbose', action='store_true')
    if len(sys.argv) < 1:
        parser.print_help()
        sys.exit(1)
    args = parser.parse_args()

    # get OS_* environment variables
    os_auth_url = get_environ('OS_AUTH_URL', args.verbose)
    os_username = get_environ('OS_USERNAME', args.verbose)
    os_password = get_environ('OS_PASSWORD', args.verbose)
    os_tenant_name = get_environ('OS_TENANT_NAME', args.verbose)
    os_region_name = get_environ('OS_REGION_NAME', args.verbose)

    # Openstack clients API
    api = openstackapi.OpenstackAPI(os_auth_url, os_username, os_password, os_project_name=os_tenant_name)

    # regions to use
    region_names = [os_region_name]
    if args.all_regions:
        # all regions available
        region_names = api.get_all_regions()

    for region in region_names:
        # get Nova client for the region
        nova = api.nova(region)

        hyp = collect_hypervisor_information(
            nova,
            verbose=args.verbose,
            remote_user=args.remote_user,
            blindly_trust_host_keys=args.blindly_trust_host_keys,
            processes=args.processes)
        srv = collect_server_information(nova, verbose=args.verbose)

        report_server_hypervisor_inconsistencies(
            srv, hyp,
            verbose=args.verbose,
            note_incomplete=not args.no_note_incomplete)

if __name__ == '__main__':
    main()
