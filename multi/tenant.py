#!/usr/bin/env python
#
# Copyright 2014 Catalyst IT Ltd
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import argparse
import os
import sys
import six
import traceback
import prettytable

from cinderclient.v1 import client as cinder_client
from glanceclient import client as glance_client
from oslo_utils import importutils
from oslo_utils import encodeutils
from heatclient import client as heat_client
from keystoneclient.v2_0 import client as keystone_client
from neutronclient.v2_0 import client as neutron_client
try:
    from novaclient.v2 import client as nova_client
except:
    from novaclient.v3 import client as nova_client
from swiftclient import client as swift_client
from swiftclient import exceptions as swift_exceptions

DNS_NAMESERVERS = ['202.78.240.213', '202.78.240.214', '202.78.240.215']


def arg(*args, **kwargs):
    def _decorator(func):
        func.__dict__.setdefault('arguments', []).insert(0, (args, kwargs))
        return func
    return _decorator


class TenantShell(object):

    def get_base_parser(self):
            parser = argparse.ArgumentParser(
                prog='tenant',
                description='Tenant management script for Catalyst Cloud.',
                add_help=False,
            )

            # Global arguments
            parser.add_argument('-h', '--help',
                                action='store_true',
                                help=argparse.SUPPRESS,
                                )

            parser.add_argument('-a', '--os-auth-url', metavar='OS_AUTH_URL',
                                type=str, required=False, dest='OS_AUTH_URL',
                                default=os.environ.get('OS_AUTH_URL', None),
                                help='Keystone Authentication URL')

            parser.add_argument('-u', '--os-username', metavar='OS_USERNAME',
                                type=str, required=False, dest='OS_USERNAME',
                                default=os.environ.get('OS_USERNAME', None),
                                help='Username for authentication')

            parser.add_argument('-p', '--os-password', metavar='OS_PASSWORD',
                                type=str, required=False, dest='OS_PASSWORD',
                                default=os.environ.get('OS_PASSWORD', None),
                                help='Password for authentication')

            parser.add_argument('-t', '--os-tenant-name',
                                metavar='OS_TENANT_NAME',
                                type=str, required=False,
                                dest='OS_TENANT_NAME',
                                default=os.environ.get('OS_TENANT_NAME', None),
                                help='Tenant name for authentication')

            parser.add_argument('-r', '--os-region-name',
                                metavar='OS_REGION_NAME',
                                type=str, required=False,
                                dest='OS_REGION_NAME',
                                default=os.environ.get('OS_REGION_NAME', None),
                                help='Region for authentication')

            parser.add_argument('-c', '--os-cacert', metavar='OS_CACERT',
                                dest='OS_CACERT',
                                default=os.environ.get('OS_CACERT'),
                                help='Path of CA TLS certificate(s) used to '
                                'verify the remote server\'s certificate. '
                                'Without this option glance looks for the '
                                'default system CA certificates.')

            parser.add_argument('-k', '--insecure',
                                default=False,
                                action='store_true', dest='OS_INSECURE',
                                help='Explicitly allow script to perform '
                                '\"insecure SSL\" (https) requests. '
                                'The server\'s certificate will not be '
                                'verified against any certificate authorities.'
                                ' This option should be used with caution.')
            return parser

    def get_subcommand_parser(self):
        parser = self.get_base_parser()
        self.subcommands = {}
        subparsers = parser.add_subparsers(metavar='<subcommand>')
        submodule = importutils.import_module('tenant')
        self._find_actions(subparsers, submodule)
        self._find_actions(subparsers, self)
        return parser

    def _find_actions(self, subparsers, actions_module):
        for attr in (a for a in dir(actions_module) if a.startswith('do_')):
            command = attr[3:].replace('_', '-')
            callback = getattr(actions_module, attr)
            desc = callback.__doc__ or ''
            help = desc.strip().split('\n')[0]
            arguments = getattr(callback, 'arguments', [])

            subparser = subparsers.add_parser(command,
                                              help=help,
                                              description=desc,
                                              add_help=False,
                                              formatter_class=HelpFormatter
                                              )
            subparser.add_argument('-h', '--help',
                                   action='help',
                                   help=argparse.SUPPRESS,
                                   )
            self.subcommands[command] = subparser
            for (args, kwargs) in arguments:
                subparser.add_argument(*args, **kwargs)
            subparser.set_defaults(func=callback)

    @arg('command', metavar='<subcommand>', nargs='?',
         help='Display help for <subcommand>.')
    def do_help(self, args):
        """Display help about this program or one of its subcommands.

        """
        if getattr(args, 'command', None):
            if args.command in self.subcommands:
                self.subcommands[args.command].print_help()
            else:
                raise Exception("'%s' is not a valid subcommand" %
                                args.command)
        else:
            self.parser.print_help()

    def init_client(self, args):
        try:
            keystone = keystone_client.Client(username=args.OS_USERNAME,
                                              password=args.OS_PASSWORD,
                                              tenant_name=args.OS_TENANT_NAME,
                                              auth_url=args.OS_AUTH_URL,
                                              region_name=args.OS_REGION_NAME,
                                              cacert=args.OS_CACERT,
                                              insecure=args.OS_INSECURE)
            self.keystone = keystone
        except Exception as e:
            # FIXME(flwang): Improve the exception catching
            raise e

        try:
            neutron = neutron_client.Client(username=args.OS_USERNAME,
                                            password=args.OS_PASSWORD,
                                            tenant_name=args.OS_TENANT_NAME,
                                            auth_url=args.OS_AUTH_URL,
                                            region_name=args.OS_REGION_NAME,
                                            insecure=args.OS_INSECURE)
            self.neutron = neutron
        except Exception as e:
            raise e

        try:
            nova = nova_client.Client(username=args.OS_USERNAME,
                                      password=args.OS_PASSWORD,
                                      project_id=args.OS_TENANT_NAME,
                                      auth_url=args.OS_AUTH_URL,
                                      region_name=args.OS_REGION_NAME,
                                      insecure=args.OS_INSECURE)
            self.nova = nova
        except Exception as e:
            raise e

        try:
            client_kwargs = {
                'token': self.keystone.auth_token,
                'insecure': args.OS_INSECURE
            }

            endpoint_kwargs = {
                'service_type': 'image',
                'endpoint_type': 'publicURL',
            }

            if args.OS_REGION_NAME:
                endpoint_kwargs['attr'] = 'region'
                endpoint_kwargs['filter_value'] = args.OS_REGION_NAME

            endpoint = keystone.service_catalog.url_for(**endpoint_kwargs)
            glance = glance_client.Client('1', endpoint, **client_kwargs)
            self.glance = glance
        except Exception as e:
            raise e

        try:
            cinder = cinder_client.Client(args.OS_USERNAME,
                                          args.OS_PASSWORD,
                                          tenant_id=keystone.auth_tenant_id,
                                          auth_url=args.OS_AUTH_URL,
                                          region_name=args.OS_REGION_NAME,
                                          insecure=args.OS_INSECURE)
            self.cinder = cinder
        except Exception as e:
            raise e

    def main(self, argv):
        parser = self.get_base_parser()
        (options, args) = parser.parse_known_args(argv)

        subcommand_parser = self.get_subcommand_parser()
        self.parser = subcommand_parser

        if options.help or not argv:
            self.do_help(options)
            return 0

        args = subcommand_parser.parse_args(argv)
        if args.func == self.do_help:
            self.do_help(args)
            return 0

        try:
            self.init_client(args)
            args.func(self, args)
        except Exception as e:
            raise e


class HelpFormatter(argparse.HelpFormatter):
    def start_section(self, heading):
        # Title-case the headings
        heading = '%s%s' % (heading[0].upper(), heading[1:])
        super(HelpFormatter, self).start_section(heading)


@arg('--tenant-name', type=str, metavar='TENANT_NAME', dest='TENANT_NAME',
     help='New tenant name (must be unique).')
@arg('--tenant-description', type=str, default=None, metavar='TENANT_DESC',
     dest='TENANT_DESC', help='Description of new tenant. Default is none.')
@arg('--meter-label-name', type=str, metavar='METER_LABEL_NAME',
     dest='METER_LABEL_NAME', help='Neutron meter label name which will be '
     'associated with the tenant')
@arg('--meter-label-description', type=str, default=None,
     metavar='METER_LABEL_DESC', dest='METER_LABEL_DESC',
     help='Description of new meter label. Default is none.')
@arg('--network-name', type=str, required=False, metavar='NETWORK_NAME',
     dest='NETWORK_NAME', help='New network name for the tenant.')
@arg('--subnet-name', type=str, required=False, metavar='SUBNET_NAME',
     dest='SUBNET_NAME', help='New subnet name for the new network.')
@arg('--subnet-cidr', type=str, required=False, metavar='SUBNET_CIDR',
     dest='SUBNET_CIDR', help='Subnet IP range with CIDR format.')
@arg('--dns-server', type=str, required=False, metavar='DNS_SERVER',
     action='append', dest='DNS_SERVER',
     help='DNS server, following the format like: '
     '--dns-server 10.0.0.1 --dns-server 10.0.0.2')
@arg('--router-name', type=str, required=False, metavar='ROUTER_NAME',
     dest='ROUTER_NAME', help='Router name associated with the new network.')
@arg('--public-network', type=str, required=False,
     metavar='PUBLIC_NETWORK', dest='PUBLIC_NETWORK',
     help='Public network id which the new router will use.')
@arg('--meter-rule-direction', type=str, required=False, default='both',
     choices=('ingress', 'egress', 'both'),
     metavar='METER_RULE_DIRECTION', dest='METER_RULE_DIRECTION',
     help='Direction of meter label rule.')
def do_init(shell, args):
    """Add a new tenant and initialize related resources."""
    print('>>> CHECK CAPACITY')
    raw_input('CAUTION: Sort out capacity planning first.')

    print('>>> CREATE TENANT')
    tenant_id = create_tenant(shell.keystone, args)

    print('>>> ADD ADMIN TO THE NEW TENANT')
    add_admin_to_tenant(shell.keystone, tenant_id)

    print('>>> CREATE NETWORK')
    network_id = create_network(shell.neutron, tenant_id, args.NETWORK_NAME)

    print('>>> CREATE SUBNET')
    subnet = create_subnet(shell.neutron, tenant_id, network_id,
                           args.SUBNET_NAME, args.SUBNET_CIDR,
                           args.DNS_SERVER)

    print('>>> CREATE ROUTER')
    router = create_router(shell.neutron, tenant_id, args.PUBLIC_NETWORK,
                           args.ROUTER_NAME)

    print('>>> CREATE INTERFACE')
    create_interface(shell.neutron, router, subnet['subnet']['id'])

    # Comment out metering label before we fixed the issue when it works with
    # VPNaaS.
    # print('>>> CREATE METER LABEL')
    # meter_label_id = create_meter_label(shell.neutron, args, tenant_id)

    # print('>>> CREATE METER LABEL RULE')
    # direction = args.METER_RULE_DIRECTION
    # if direction in ('ingress', 'egress'):
    #    create_meter_label_rule(shell.neutron, meter_label_id, direction)
    # elif direction == 'both':
    #    create_meter_label_rule(shell.neutron, meter_label_id, 'ingress')
    #    create_meter_label_rule(shell.neutron, meter_label_id, 'egress')

    print('>>> COMPLETE SUCCESSFULLY')


@arg('--label-name-template', type=str, metavar='LABEL_NAME_TEMPLATE',
     dest='LABEL_NAME_TEMPLATE', default='meter-label-{0}',
     help='Define a name template to add meter label for existed tenants. '
     'Such as: meter-label-{0}, {0} will be replaced by the tenant name'
     ' automatically.')
@arg('--meter-rule-direction', type=str, required=False, default='both',
     choices=('ingress', 'egress', 'both'),
     metavar='METER_RULE_DIRECTION', dest='METER_RULE_DIRECTION',
     help='Direction of meter label rule.')
def do_meter(shell, args):
    """Add meter label for all existed tenants for network traffic billing.

    """
    print('>>> TENANT LIST MISSING METER LABEL')
    tenants = shell.keystone.tenants.list()
    meter_labels = shell.neutron.list_metering_labels()

    dict_tenants = {}
    for tenant in tenants:
        dict_tenants[tenant.id] = tenant
    for label in meter_labels['metering_labels']:
        if label['tenant_id'] in dict_tenants.keys():
            del dict_tenants[label['tenant_id']]
    print_list(dict_tenants.values(), ['id', 'name', 'enabled'])
    if len(dict_tenants.values()) <= 0:
        print('>>> ALL TENANTS HAVE METER LABEL')
        return 0
    answer = raw_input('Create meter label/rules for above tenants(Y/n)?')
    if answer.lower() == 'y':
        for tenant in dict_tenants.values():
            label_name = args.LABEL_NAME_TEMPLATE.format(tenant.name)
            args.METER_LABEL_NAME = label_name
            args.METER_LABEL_DESC = 'Meter label of {0}'.format(tenant.name)
            meter_label_id = create_meter_label(shell.neutron, args, tenant.id)
            if meter_label_id:
                direction = args.METER_RULE_DIRECTION
                if direction in ('ingress', 'egress'):
                    create_meter_label_rule(shell.neutron, meter_label_id,
                                            direction)
                elif direction == 'both':
                    create_meter_label_rule(shell.neutron, meter_label_id,
                                            'ingress')
                    create_meter_label_rule(shell.neutron, meter_label_id,
                                            'egress')
    print('>>> COMPLETE SUCCESSFULLY')


@arg('--tenant-id', type=str, metavar='TENANT_ID',
     dest='TENANT_ID', required=True,
     help='ID of the tenant to be deleted.')
@arg('--auto-clean', type=bool, metavar='AUTO_CLEAN',
     dest='AUTO_CLEAN', default=False,
     help='Auto clean all resources.')
def do_delete(shell, args):
    """Delete tenant and all resources associated with it to avoid leaving
    any legacy stuff
    """

    tenant = shell.keystone.tenants.get(args.TENANT_ID)
    shell.tenant = tenant

    if not prompt_yes_no('Tenant [%s] will be deleted. '
                         'Please confirm to continue.' % tenant.name,
                         default='yes'):
        return

    component_list = ['nova', 'neutron', 'cinder', 'glance', 'swift', 'heat',
                      'keystone']

    myself = __import__('tenant')
    for component in component_list:
        callback = getattr(myself, component.lower() + '_delete')
        print('>>> TO DELETE ' + component.upper())
        try:
            callback(shell, args)
        except Exception as e:
            print(e)
    print('\n\nTenant %s has been cleaned up based on above selections.' %
          args.TENANT_ID)


def keystone_delete(shell, args):
    try:
        if(args.AUTO_CLEAN or prompt_yes_no('Please confirm to delete the'
                                            ' tenant from Keystone:')):
            shell.keystone.tenants.delete(args.TENANT_ID)
    except Exception as e:
        raise e


def nova_delete(shell, args):
    # NOTE(flwang): Seems there is a bug for nova, it doesn't honour the
    # project id though based on the code it does. Will dig it later.
    print('>>>>>> SERVERS(VM) LIST')
    servers = shell.nova.servers.list(search_opts={'all_tenants': True})
    servers = [s for s in servers if s.tenant_id == args.TENANT_ID]
    print_list(servers, ['id', 'name', 'status', 'tenant_id'])

    if (len(servers) and (args.AUTO_CLEAN or
                          prompt_yes_no('Please confirm:'))):
            for server in servers:
                shell.nova.servers.delete(server.id)


def glance_delete(shell, args):
    images = shell.glance.images.list(owner=args.TENANT_ID)
    # NOTE(flwang): Make sure the images are what we want to delete
    images = [img for img in images if img.owner == args.TENANT_ID]
    print_list(images, ['id', 'name', 'owner'])

    if (len(images) and (args.AUTO_CLEAN or
                         prompt_yes_no('Please confirm:'))):
            for image in images:
                shell.glance.images.delete(image.id)


def cinder_delete(shell, args):
    print('>>>>>> VOLUME SNAPSHOTS')
    # Delete snapshots
    snapshots = shell.cinder.volume_snapshots.list(search_opts={'all_tenants':
                                                                True})
    tenant_attr = 'os-extended-snapshot-attributes:project_id'
    # NOTE(flwang): If the script user is admin then it will get all the
    # snapshot and each snapshot will have the attribute
    # 'os-extended-snapshot-attributes:project_id' to indicate the tenant.
    # For non-admin, there is no that attribute.
    user_roles = shell.keystone.session.auth.auth_ref['user']['roles']
    if {u'name': u'admin'} in user_roles:
        snapshots = [v for v in snapshots
                     if getattr(v, tenant_attr) == args.TENANT_ID]
        print_list(snapshots, ['id', 'display_name', 'status', tenant_attr])
    else:
        print_list(snapshots, ['id', 'display_name', 'status'])

    if (len(snapshots) and (args.AUTO_CLEAN or
                            prompt_yes_no('Please confirm:'))):
            for snapshot in snapshots:
                shell.cinder.volume_snapshots.delete(snapshot.id)

    print('>>>>>> VOLUMES')
    # Delete volumes
    volumes = shell.cinder.volumes.list(search_opts={'all_tenants': True})
    tenant_attr = 'os-vol-tenant-attr:tenant_id'
    if {u'name': u'admin'} in user_roles:
        volumes = [v for v in volumes
                   if getattr(v, tenant_attr) == args.TENANT_ID]
        print_list(volumes, ['id', 'display_name', 'status', tenant_attr])
    else:
        print_list(volumes, ['id', 'display_name', 'status'])

    if (len(volumes) and (args.AUTO_CLEAN or
                          prompt_yes_no('Please confirm:'))):
            for volume in volumes:
                shell.cinder.volumes.delete(volume.id)


def swift_delete(shell, args):
    endpoint = shell.keystone.service_catalog.url_for(service_type='object-store')  # noqa
    url = endpoint.split('_')[0] + '_' + args.TENANT_ID

    try:
        # Get a specific token for swift
        ks = keystone_client.Client(username=args.OS_USERNAME,
                                    password=args.OS_PASSWORD,
                                    tenant_name=shell.tenant.name,
                                    auth_url=args.OS_AUTH_URL,
                                    region_name=args.OS_REGION_NAME,
                                    cacert=args.OS_CACERT,
                                    insecure=args.OS_INSECURE)
        account = getattr(swift_client, 'get_account')(url, ks.auth_token)
        print_list(account[1], ['name', 'count', 'bytes'])
        if (len(account[1]) and (args.AUTO_CLEAN or
                                 prompt_yes_no('Please confirm:'))):
            for co in account[1]:
                co_obj = getattr(swift_client, 'get_container')(url,
                                                                ks.auth_token,
                                                                co['name'])
                # Delete objects firstly
                for obj in co_obj[1]:
                    getattr(swift_client,
                            'delete_object')(url, ks.auth_token,
                                             container=co['name'],
                                             name=obj['name'])
                # Delete container
                getattr(swift_client, 'delete_container')(url,
                                                          ks.auth_token,
                                                          co['name'])
    except swift_exceptions.ClientException as e:
        print('%s %s' % (e.http_status, e.http_reason))


def neutron_delete(shell, args):
    # vpn service
    _delete_targeted_tenant_resource(shell, args, 'ipsec_site_connection')
    _delete_targeted_tenant_resource(shell, args, 'ipsecpolicy')
    _delete_targeted_tenant_resource(shell, args, 'ikepolicy')
    _delete_targeted_tenant_resource(shell, args, 'vpnservice')

    # meter label and rules
    print('>>>>>> METER LABEL RULE LIST')
    if not hasattr(shell.neutron, 'list_metering_labels'):
        return
    metering_labels = shell.neutron.list_metering_labels()['metering_labels']
    metering_label_rules = shell.neutron.list_metering_label_rules()
    metering_label_rules = metering_label_rules['metering_label_rules']

    targeted_rules = []
    for rule in metering_label_rules:
        if rule['metering_label_id'] in [m['id'] for m in metering_labels
                                         if m['tenant_id'] == args.TENANT_ID]:
            targeted_rules.append(rule)
    print_list(targeted_rules, ['id', 'name', 'tenant_id'])

    if (len(targeted_rules) and (args.AUTO_CLEAN or
                                 prompt_yes_no('Please confirm:'))):
            for rule in targeted_rules:
                shell.neutron.delete_metering_label_rule(rule['id'])

    print('>>>>>> METER LABEL LIST')
    metering_labels = [m for m in metering_labels
                       if m['tenant_id'] == args.TENANT_ID]
    print_list(metering_labels, ['id', 'name', 'tenant_id'])
    if (len(metering_labels) and (args.AUTO_CLEAN or
                                  prompt_yes_no('Please confirm:'))):
        for label in metering_labels:
            shell.neutron.delete_metering_label(label['id'])

    # port
    print('>>>>>> PORT LIST')
    ports = shell.neutron.list_ports()
    targeted_ports = []
    for port in ports['ports']:
        if port['tenant_id'] == args.TENANT_ID:
            targeted_ports.append(port)
    print_list(targeted_ports, ['id', 'name', 'tenant_id'])

    if (len(targeted_ports) and (args.AUTO_CLEAN or
                                 prompt_yes_no('Please confirm:'))):
        for port in targeted_ports:
            try:
                if port['device_owner'] == 'network:router_gateway':
                    shell.neutron.remove_gateway_router(port['device_id'])
                elif port['device_owner'] == 'network:router_interface':
                    for subnet in port['fixed_ips']:
                        body = {'subnet_id': subnet['subnet_id']}
                        shell.neutron.remove_interface_router(
                            port['device_id'], body)
                else:
                    shell.neutron.delete_port(port['id'])
            except Exception as e:
                print('Failed to delete port:{0}, see: {1}'.
                      format(port['id'], str(e)))
                continue

    # security group
    _delete_targeted_tenant_resource(shell, args, 'security_group')

    # floating IP
    _delete_targeted_tenant_resource(shell, args, 'floatingip')

    # sub net
    _delete_targeted_tenant_resource(shell, args, 'subnet')

    # router
    _delete_targeted_tenant_resource(shell, args, 'router')

    # network
    _delete_targeted_tenant_resource(shell, args, 'network')


def heat_delete(shell, args):
    print('>>>>>> STACKS LIST')
    try:
        heat_srv = shell.keystone.services.find(type='orchestration')
        heat_endpoint = shell.keystone.endpoints.find(service_id=heat_srv.id)
        heat_url = heat_endpoint.publicurl.replace('$(tenant_id)s',
                                                   args.TENANT_ID)
        heat = heat_client.Client('1', endpoint=heat_url,
                                  token=shell.keystone.auth_token)
    except Exception as e:
        raise e

    stacks = heat.stacks.list()
    stacks = [s for s in stacks]
    print_list(stacks, ['id', 'stack_name', 'stack_status'])

    if (len(stacks) and (args.AUTO_CLEAN or
                         prompt_yes_no('Please confirm:'))):
            for stack in stacks:
                heat.stacks.delete(stack.id)


def _delete_targeted_tenant_resource(shell, args, resource):
    print('>>>>>> %s LIST' % resource.upper())
    list_command = 'list_{0}s'.format(resource)
    if resource in ('ipsecpolicy', 'ikepolicy'):
        list_command = list_command.replace('policy', 'policie')
    resources = getattr(shell.neutron, list_command)()

    resp_key = resource + 's'
    if resource in ('ipsecpolicy', 'ikepolicy'):
        resp_key = resp_key.replace('policy', 'policie')
    delete_resources = []
    for res in resources[resp_key]:
        if res['tenant_id'] == args.TENANT_ID:
            delete_resources.append(res)
    print_list(delete_resources, ['id', 'name', 'tenant_id'])

    if (len(delete_resources) and (args.AUTO_CLEAN or
                                   prompt_yes_no('Please confirm:'))):
        delete_function = getattr(shell.neutron,
                                  'delete_{0}'.format(resource))
        for res in delete_resources:
            delete_function(res['id'])


@arg('--auto-clean', type=bool, metavar='AUTO_CLEAN',
     dest='AUTO_CLEAN', default=False,
     help='Auto clean legacy resources.')
@arg('--component', type=str, metavar='COMPONENT',
     dest='COMPONENT',
     help='Specific component to audit.')
def do_audit(shell, args):
    """Audit all existed tenants to make sure everything is OK.

    Tenant deletion related blueprints:
    [1] https://blueprints.launchpad.net/keystone/+spec/notifications
    [2] https://blueprints.launchpad.net/neutron/+spec/tenant-delete
    """
    user_roles = shell.keystone.session.auth.auth_ref['user']['roles']
    if {u'name': u'admin'} not in user_roles:
        print('Admin permission is required.')
        return

    component_list = ['nova', 'neutron', 'cinder', 'glance']

    tenants = shell.keystone.tenants.list()
    tenant_ids = [t.id for t in tenants]

    myself = __import__('tenant')
    if args.COMPONENT:
        callback = getattr(myself, args.COMPONENT.lower() + '_audit')
        print('>>> AUDITING ' + args.COMPONENT.upper())
        callback(shell, args, tenant_ids)
    else:
        for component in component_list:
            callback = getattr(myself, component.lower() + '_audit')
            print('>>> AUDITING ' + component.upper())
            callback(shell, args, tenant_ids)


def nova_audit(shell, args, tenant_ids):
    # instance
    print('>>>>>> ZOMBIE INSTANCE LIST')
    servers = shell.nova.servers.list(search_opts={'all_tenants': True})
    zombie_servers = [s for s in servers if s.tenant_id not in tenant_ids]
    print_list(zombie_servers, ['id', 'name', 'tenant_id'])

    if ((len(zombie_servers) and
         (args.AUTO_CLEAN or prompt_yes_no('Confirm to delete:')))):
        for server in zombie_servers:
            shell.nova.servers.delete(server.id)


def neutron_audit(shell, args, tenant_ids):
    # Clean up services, FWaaS, LBaaS, etc
    _clean_up_resource(shell, args, tenant_ids, 'ipsec_site_connection')
    _clean_up_resource(shell, args, tenant_ids, 'ipsecpolicy')
    _clean_up_resource(shell, args, tenant_ids, 'ikepolicy')
    _clean_up_resource(shell, args, tenant_ids, 'vpnservice')

    # metering label
    _clean_up_resource(shell, args, tenant_ids, 'metering_label')

    # meter label rule
    print('>>>>>> ZOMBIE METER LABEL RULE LIST')
    metering_labels = shell.neutron.list_metering_labels()
    metering_label_ids = [m['id'] for m in metering_labels['metering_labels']]
    metering_label_rules = shell.neutron.list_metering_label_rules()
    zombie_metering_label_rules = []
    for metering_label_rule in metering_label_rules['metering_label_rules']:
        if metering_label_rule['metering_label_id'] not in metering_label_ids:
            zombie_metering_label_rules.append(metering_label_rule)
    print_list(zombie_metering_label_rules, ['id', 'name', 'tenant_id'])

    if ((len(zombie_metering_label_rules) > 0 and
         (args.AUTO_CLEAN or prompt_yes_no('Confirm to delete:')))):
        for metering_label_rule in zombie_metering_label_rules:
            shell.neutron.delete_metering_label_rule(metering_label_rule['id'])

    # floating ip
    _clean_up_resource(shell, args, tenant_ids, 'floatingip')

    # port
    print('>>>>>> ZOMBIE PORT LIST')
    ports = shell.neutron.list_ports()
    zombie_ports = []
    for port in ports['ports']:
        if port['tenant_id'] not in tenant_ids:
            zombie_ports.append(port)
    print_list(zombie_ports, ['id', 'name', 'tenant_id'])

    if (len(zombie_ports) > 0 and (args.AUTO_CLEAN or
                                   prompt_yes_no('Confirm to delete:'))):
        for port in zombie_ports:
            try:
                if port['device_owner'] == 'network:router_gateway':
                    shell.neutron.remove_gateway_router(port['device_id'])
                elif port['device_owner'] == 'network:router_interface':
                    for subnet in port['fixed_ips']:
                        body = {'subnet_id': subnet['subnet_id']}
                        shell.neutron.remove_interface_router(
                            port['device_id'], body)
                else:
                    shell.neutron.delete_port(port['id'])
            except Exception as e:
                print('Failed to delete port:{0}, see: {1}'.format(port['id'],
                                                                   str(e)))
                continue

    # security group
    _clean_up_resource(shell, args, tenant_ids, 'security_group')

    # subnet
    _clean_up_resource(shell, args, tenant_ids, 'subnet')

    # router
    _clean_up_resource(shell, args, tenant_ids, 'router')

    # network
    _clean_up_resource(shell, args, tenant_ids, 'network')


def _clean_up_resource(shell, args, tenant_ids, resource):
    print('>>>>>> ZOMBIE %s LIST' % resource.upper())
    resources = getattr(shell.neutron, 'list_{0}s'.format(resource))()
    zombie_resources = [r for r in resources[resource + 's']
                        if r['tenant_id'] not in tenant_ids]
    print_list(zombie_resources, ['id', 'name', 'tenant_id'])

    if (len(zombie_resources) > 0 and (args.AUTO_CLEAN or
                                       prompt_yes_no('Confirm to delete:'))):
        delete_function = getattr(shell.neutron, 'delete_{0}'.format(resource))
        for res in zombie_resources:
            delete_function(res['id'])


def cinder_audit(shell, args, tenant_ids):
    print('>>>>>> ZOMBIE VOLUME SNAPSHOTS LIST')
    # snapshots
    snapshots = shell.cinder.volume_snapshots.list(search_opts={'all_tenants':
                                                                True})
    tenant_attr = 'os-extended-snapshot-attributes:project_id'
    zombie_snapshots = [s for s in snapshots
                        if getattr(s, tenant_attr) not in tenant_ids]
    print_list(zombie_snapshots, ['id', 'display_name', 'status', tenant_attr])

    if (len(zombie_snapshots) > 0 and (args.AUTO_CLEAN or
                                       prompt_yes_no('Confirm to delete:'))):
            for snapshot in zombie_snapshots:
                shell.cinder.volume_snapshots.delete(snapshot.id)

    # volume
    print('>>>>>> ZOMBIE VOLUME LIST')
    volumes = shell.cinder.volumes.list(search_opts={'all_tenants': True})
    tenant_attr = 'os-vol-tenant-attr:tenant_id'
    zombie_volumes = [v for v in volumes
                      if getattr(v, tenant_attr) not in tenant_ids]
    print_list(zombie_volumes, ['id', 'display_name',
                                'os-vol-tenant-attr:tenant_id'])

    if (len(zombie_volumes) > 0 and (args.AUTO_CLEAN or
                                     prompt_yes_no('Confirm to delete:'))):
        for volume in zombie_volumes:
            shell.cinder.volumes.delete(volume.id)


def glance_audit(shell, args, tenant_ids):
    # image
    print('>>>>>> ZOMBIE IMAGE LIST')
    images = shell.glance.images.list(filters={"is_public": None})
    zombie_images = [i for i in images if (i.owner not in
                                           tenant_ids) and (not i.is_public)]
    print_list(zombie_images, ['id', 'name', 'owner'])

    if (len(zombie_images) > 0 and (args.AUTO_CLEAN or
                                    prompt_yes_no('Confirm to delete:'))):
        for image in zombie_images:
            shell.glance.images.delete(image.id)


def swift_audit(shell, args, tenant_ids):
    # TODO(flwang): Seems Swift can't get all the resources with admin
    # because all its resources will be associated with a tenant. That means
    # without tenant id, you can't list them. So it's hard to detect the
    # zombie resources.
    pass


def create_tenant(keystone, args):
    try:
        tenant = keystone.tenants.create(tenant_name=args.TENANT_NAME,
                                         description=args.TENANT_DESC,
                                         enabled=True)
        print_dict(tenant._info)
    except Exception as e:
        raise e
    return tenant.id


def add_admin_to_tenant(keystone, tenant_id):
    # Add admin user into the new tenant since it is required for monitoring
    try:
        admin_user_id, admin_role_id = get_admin_user_role(keystone)
        keystone.roles.add_user_role(admin_user_id, admin_role_id, tenant_id)
    except Exception as e:
        raise e


def get_admin_user_role(keystone):
    # NOTE(flwang): Here is assuming that both the admin name and role name
    # using 'admin' as the name.
    try:
        admin_user_id = [r.id for r in keystone.users.list()
                         if r.name == 'admin']
        admin_role_id = [r.id for r in keystone.roles.list()
                         if r.name == 'admin']
        return (admin_user_id[0], admin_role_id[0])
    except Exception as e:
        raise e


def create_network(neutron, tenant_id, network_name):
    if not network_name:
        network_name = raw_input('Please enter the network name:')
    try:
        network_body = {
            "network": {
                "name": network_name,
                'tenant_id': tenant_id,
                "admin_state_up": True
            }
        }
        network = neutron.create_network(body=network_body)
        print_dict(network['network'])
        return network['network']['id']
    except Exception as e:
        raise e


def create_subnet(neutron, tenant_id, network_id, subnet_name, subnet_cidr,
                  dns_servers):
    if not subnet_cidr:
        subnet_cidr = raw_input('Please enter the IP range(CIDR format):')
    try:
        dns_servers = dns_servers if dns_servers else DNS_NAMESERVERS
        subnet_body = {
            "subnet": {
                "network_id": network_id,
                "ip_version": 4,
                'tenant_id': tenant_id,
                'dns_nameservers': dns_servers,
                "cidr": subnet_cidr
            }
        }
        subnet = neutron.create_subnet(body=subnet_body)
        print_dict(subnet['subnet'])
        return subnet
    except Exception as e:
        raise e


def create_router(neutron, tenant_id, public_network, router_name):
    if not router_name:
        router_name = raw_input('Please enter the router name:')
    if not public_network:
        public_network = raw_input('Please enter the public network id:')
    try:
        router_body = {
            "router": {
                "name": router_name,
                "external_gateway_info": {
                    "network_id": public_network
                },
                'tenant_id': tenant_id,
                "admin_state_up": True
            }
        }
        router = neutron.create_router(body=router_body)
        print_dict(router['router'])
        return router
    except Exception as e:
        raise e


def create_interface(neutron, router, subnet_id):
    try:
        interface_body = {
            "subnet_id": subnet_id
        }
        interface = neutron.add_interface_router(router['router']['id'],
                                                 body=interface_body)
        print_dict(interface)
    except Exception as e:
        raise e


def create_meter_label(neutron, args, tenant_id):
    try:
        meter_label_name = args.METER_LABEL_NAME
        if not meter_label_name:
            meter_label_name = 'meter-label-' + args.TENANT_NAME

        meter_label_body = {
            'metering_label': {
                'name': meter_label_name,
                'tenant_id': tenant_id,
                'description': args.METER_LABEL_DESC,
            }
        }
        meter_label = neutron.create_metering_label(body=meter_label_body)
        print_dict(meter_label['metering_label'])
        return meter_label['metering_label']['id']
    except Exception as e:
        raise e


def create_meter_label_rule(neutron, meter_label_id, direction):
    try:
        meter_rule_body = {"metering_label_rule":
                           {"remote_ip_prefix": "0.0.0.0/0",
                            "direction": direction,
                            "metering_label_id": meter_label_id
                            }
                           }
        meter_rule = neutron.create_metering_label_rule(body=meter_rule_body)
        print_dict(meter_rule['metering_label_rule'])
    except Exception as e:
        raise e


def rollback(args, **parms):
    # TODO(flwang): Remove the created resources if there is any failure.
    pass


def print_list(objs, fields, formatters={}):
    pt = prettytable.PrettyTable([f for f in fields], caching=False)
    pt.align = 'l'

    for o in objs:
        row = []
        for field in fields:
            if field in formatters:
                row.append(formatters[field](o))
            else:
                field_name = field.lower().replace(' ', '_')
                if type(o) == dict and field in o:
                    data = o[field_name]
                else:
                    data = getattr(o, field_name, None) or ''
                row.append(data)
        pt.add_row(row)

    print(encodeutils.safe_encode(pt.get_string()))


def prompt_yes_no(question, default="no"):
    """Ask a yes/no question via raw_input() and return their answer.

    "question" is a string that is presented to the user.
    "default" is the presumed answer if the user just hits <Enter>.
        It must be "yes" (the default), "no" or None (meaning
        an answer is required of the user).

    The "answer" return value is one of "yes" or "no".
    """
    valid = {"yes": True, "y": True, "ye": True,
             "no": False, "n": False}
    if default is None:
        prompt = " [y/n] "
    elif default == "yes":
        prompt = " [Y/n] "
    elif default == "no":
        prompt = " [y/N] "
    else:
        raise ValueError("invalid default answer: '%s'" % default)

    while True:
        sys.stdout.write(question + prompt)
        choice = raw_input().lower()
        if default is not None and choice == '':
            return valid[default]
        elif choice in valid:
            return valid[choice]
        else:
            sys.stdout.write("Please respond with 'yes' or 'no' "
                             "(or 'y' or 'n').\n")


def print_dict(d, max_column_width=80):
    pt = prettytable.PrettyTable(['Property', 'Value'], caching=False)
    pt.align = 'l'
    pt.max_width = max_column_width
    [pt.add_row(list(r)) for r in six.iteritems(d)]
    print(encodeutils.safe_encode(pt.get_string(sortby='Property')))


if __name__ == '__main__':
    try:
        TenantShell().main(sys.argv[1:])
    except KeyboardInterrupt:
        print("Terminating...")
        sys.exit(1)
    except Exception as e:
        exc_type, exc_value, exc_traceback = sys.exc_info()
        traceback.print_exception(exc_type, exc_value, exc_traceback,
                                  limit=2, file=sys.stdout)
