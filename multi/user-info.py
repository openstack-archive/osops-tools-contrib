#!/usr/bin/env python
#
#  Copyright (c) 2015 SWITCH http://www.switch.ch
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

# Author: Valery Tschopp <valery.tschopp@switch.ch>
# Date: 2015-08-27
# Update: 2016-04-04 - all regions from keystone v3 api

import sys
import traceback
import os
import argparse
import keystoneclient
import novaclient
from keystoneclient.v3 import client as keystone_v3
from novaclient import client as nova_client
from cinderclient.v2 import client as cinder_client
from neutronclient.v2_0 import client as neutron_client
from glanceclient.v2 import client as glance_client

def get_environ(key, verbose=False):
    if key not in os.environ:
        print "ERROR:", key, "not define in environment"
        sys.exit(1)
    if verbose:
        if 'password' in key.lower():
            key_value = '*' * len(os.environ[key])
        else:
            key_value = os.environ[key]
        print "{}: {}".format(key, key_value)
    return os.environ[key]


def main():
    """Show information (servers, volumes, networks, ...) for a user.

    Search in all projects the user is member of, and optionally in all regions (-a|--all).
    """
    parser = argparse.ArgumentParser(
        description="Show information (servers, volumes, networks, ...) for a user. Search in all projects the user is member of, and optionally in all regions (-a).")
    parser.add_argument('-a', '--all-regions', help='query all regions', action='store_true')
    parser.add_argument('USERNAME', help="username to search")
    parser.add_argument('-v', '--verbose', help='verbose', action='store_true')
    if len(sys.argv) < 2:
        parser.print_help()
        sys.exit(1)
    args = parser.parse_args()

    # get OS_* environment variables
    os_auth_url = get_environ('OS_AUTH_URL', args.verbose)
    os_username = get_environ('OS_USERNAME', args.verbose)
    os_password = get_environ('OS_PASSWORD', args.verbose)
    os_tenant_name = get_environ('OS_TENANT_NAME', args.verbose)
    os_region_name = get_environ('OS_REGION_NAME', args.verbose)

    # keystone_V3 client requires a /v3 auth url
    if '/v2.0' in os_auth_url:
        os_auth_url_v3 = os_auth_url.replace('/v2.0', '/v3')
        if args.verbose:
            print "os_auth_url_v3:", os_auth_url_v3

    keystone = keystone_v3.Client(username=os_username,
                                  password=os_password,
                                  project_name=os_tenant_name,
                                  auth_url=os_auth_url_v3)

    # all regions available
    all_regions = []
    for region in keystone.regions.list():
        all_regions.append(region.id)

    # regions to use
    region_names = [os_region_name]
    if args.all_regions:
        if os_region_name in all_regions:
            region_names = all_regions

    # Openstack clients per region
    nova_regions = {}
    cinder_regions = {}
    neutron_regions = {}
    glance_regions = {}
    for region_name in region_names:
        _nova = nova_client.Client(2,
                                   os_username,
                                   os_password,
                                   os_tenant_name,
                                   auth_url=os_auth_url,
                                   region_name=region_name)
        nova_regions[region_name] = _nova
        _cinder = cinder_client.Client(os_username,
                                       os_password,
                                       os_tenant_name,
                                       auth_url=os_auth_url,
                                       region_name=region_name)
        cinder_regions[region_name] = _cinder
        _neutron = neutron_client.Client(username=os_username,
                                         password=os_password,
                                         tenant_name=os_tenant_name,
                                         auth_url=os_auth_url,
                                         region_name=region_name)
        neutron_regions[region_name] = _neutron
        _glance_endpoint = keystone.service_catalog.url_for(service_type='image',
                                                            endpoint_type='publicURL',
                                                            region_name=region_name)
        _glance = glance_client.Client(endpoint=_glance_endpoint,
                                       token=keystone.auth_token)
        glance_regions[region_name] = _glance

    try:
        username = args.USERNAME
        user = keystone.users.find(name=username)
        user_projects = keystone.projects.list(user=user)

        print u"User: {} [{}]: {} projects".format(user.name,
                                                  user.id,
                                                  len(user_projects))
        for project in user_projects:
            print u" Project: {} [{}] - {}".format(project.name,
                                                  project.id,
                                                  project.description)

            servers_search_opts = {'all_tenants': True, 'tenant_id': project.id}
            volumes_search_opts = {'all_tenants': True, 'project_id': project.id}
            neutron_search_opts = {'all_tenants': True, 'tenant_id': project.id}
            glance_search_opts = {'filters': {'owner': project.id } }
            for region in region_names:

                # get clients for region
                nova = nova_regions[region]
                cinder = cinder_regions[region]
                neutron = neutron_regions[region]
                glance = glance_regions[region]

                # servers
                project_servers = nova.servers.list(search_opts=servers_search_opts)
                servers = {}
                for server in project_servers:
                    servers[server.id] = server

                # volumes
                project_volumes = cinder.volumes.list(search_opts=volumes_search_opts)
                volumes = {}
                for volume in project_volumes:
                    volumes[volume.id] = volume

                # volume snapshots
                project_volume_snapshots = cinder.volume_snapshots.list(search_opts=volumes_search_opts)
                volume_snapshots = {}
                for volume_snapshot in project_volume_snapshots:
                    volume_snapshots[volume_snapshot.id] = volume_snapshot

                # images
                project_images = glance.images.list(**glance_search_opts)
                images = {}
                for image in project_images:
                    images[image.id] = image

                # floating IPs
                resp = neutron.list_floatingips(**neutron_search_opts)
                floatingips = {}
                for floatingip in resp['floatingips']:
                    floatingips[floatingip['id']] = floatingip

                resp = neutron.list_networks(**neutron_search_opts)
                networks = {}
                for network in resp['networks']:
                    networks[network['id']] = network

                resp = neutron.list_routers(**neutron_search_opts)
                routers = {}
                for router in resp['routers']:
                    routers[router['id']] = router

                #
                # show information
                #
                if servers or volumes or volume_snapshots or floatingips or networks or routers or images:
                    print "  Region:", region
                    if servers:
                        print "   Servers:"
                        for id, server in servers.items():
                            print u"    Server: {} [{}] - {}".format(server.name, server.id, server.status)
                            volumes_attached = getattr(server,'os-extended-volumes:volumes_attached')
                            for volume_attached in volumes_attached:
                                volume_id = volume_attached['id']
                                if volume_id in volumes:
                                    volume = volumes[volume_id]
                                    volume_name = volume.name.rstrip() if volume.name else 'None'
                                    for attachment in volume.attachments:
                                        attached_server_id = attachment['server_id']
                                        attached_device = attachment['device']
                                        if attached_server_id == server.id:
                                            print u"     Volume: {}: {} [{}] {}GB - {}".format(attached_device, volume_name, volume.id, volume.size, volume.status.upper())
                                            # remove volume from list
                                            volumes.pop(volume_id)
                                        else:
                                            print u"     ERROR: Volume {} [{}] not attached to Server {} [{}]".format(volume_name, volume.id, server.name, server.id) 

                    if volumes:
                        print "   Other Volumes:"
                        for id, volume in volumes.items():
                            volume_name = volume.name.rstrip() if volume.name else 'None'
                            print u"    Volume: {} [{}] {}GB - {}".format(volume_name, volume.id, volume.size, volume.status.upper())
                            for attachment in volume.attachments:
                                attached_server_id = attachment['server_id']
                                if attached_server_id in servers:
                                    server_attached = servers[attached_server_id]
                                    print u"     Attached to: {} [{}]:{}".format(server_attached.name, server_attached.id, attachment['device'])
                                else:
                                    print u"     ERROR: attached to unknown Server [{}]:{}".format(attached_server_id, attachment['device']) 

                    if volume_snapshots:
                        print "   Volume Snapshots:"
                        for id, v_snapshot in volume_snapshots.items():
                            v_snapshot_name = v_snapshot.name.rstrip() if v_snapshot.name else 'None'
                            print u"    Snapshot: {} [{}] (Volume: [{}]) {}GB - {}".format(v_snapshot_name, v_snapshot.id, v_snapshot.volume_id, v_snapshot.size, v_snapshot.status.upper())

                    if images:
                        print "   Images:"
                        for id, image in images.items():
                            print u"    Image: {} [{}] (Owner: [{}], Visibility: {})".format(image.name, image.id, image.owner, image.visibility)

                    if floatingips:
                        print "   Floating IPs:"
                        for id, floatingip in floatingips.items():
                            print u"    IP: {} [{}] - {}".format(floatingip['floating_ip_address'], floatingip['id'], floatingip['status'])

                    if routers:
                        print "   Routers:"
                        for id, router in routers.items():
                            print u"    Router: {} [{}] - {}".format(router['name'], router['id'], router['status'])
                            resp = neutron.list_ports(device_id=id)
                            ifaces = resp['ports']
                            for iface in ifaces:
                                device_owner = iface['device_owner']
                                iface_info = ["Subnet: %s IP: %s" % (i['subnet_id'],i['ip_address']) for i in iface['fixed_ips']]
                                if device_owner == 'network:router_gateway':
                                    resp = neutron.show_network(iface['network_id'])
                                    iface_net = resp['network']
                                    print u"     Interface: {} (Gateway External Network: {} [{}])".format(iface['id'], iface_net['name'], iface_net['id'])
                                elif device_owner == 'network:router_interface':
                                    print u"     Interface: {} ({})".format(iface['id'], ",".join(iface_info))
                                else:
                                    print u"     Interface: {} ({}) ({})".format(iface['id'], device_owner, ",".join(iface_info))

                    if networks:
                        print "   Networks:"
                        for id, network in networks.items():
                            print u"    Network: {} [{}] - {}".format(network['name'], network['id'], network['status'])
                            for subnet_id in network['subnets']:
                                resp = neutron.show_subnet(subnet_id)
                                subnet = resp['subnet']
                                subnet_ipranges = ["IPRange: %s-%s" % (i['start'],i['end']) for i in subnet['allocation_pools']]
                                print u"     Subnet: {} [{}] (CIDR: {})".format(subnet['name'], subnet['id'], subnet['cidr'])
                            resp = neutron.list_ports(network_id=id)
                            ports = resp['ports']
                            for port in ports:
                                device_id = port['device_id']
                                device_owner = port['device_owner']
                                if device_id in servers:
                                    server = servers[device_id]
                                    print u"     Port: {} (Server: {} [{}])".format(port['id'], server.name, server.id, port['status'])
                                elif device_id in routers:
                                    router = routers[device_id]
                                    print u"     Port: {} (Router: {} [{}])".format(port['id'], router['name'], router['id'], port['status'])
                                elif device_owner == 'network:dhcp':
                                    print u"     Port: {} (DHCP)".format(port['id'])
                                else:
                                    print u"     Port: {} ({} [])".format(port['id'], device_owner, device_id, port['status'])

    except keystoneclient.exceptions.NotFound as e:
        print "ERROR: Username", username, "not found:", e.message
        sys.exit(1)

    except novaclient.exceptions.NotFound as e:
        print "ERROR: not found:", e.message
        sys.exit(1)

    except UnicodeEncodeError as e:
        print "UnicodeEncodeError"
        print '-'*60
        traceback.print_exc(file=sys.stdout)
        print '-'*60
        sys.exit(1)

    except Exception as e:
        print "ERROR:", e.message
        sys.exit(1)


if __name__ == '__main__':
    main()
