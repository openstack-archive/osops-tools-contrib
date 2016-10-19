#! /usr/bin/env python
# Copyright 2013 AT&T Services, Inc.
#           2015 Catalyst IT Ltd.
# All Rights Reserved.
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
import datetime
import json
from keystoneclient.v2_0 import client as ksclient
import logging
from novaclient import client
import os
import sys
import time
LOG = logging.getLogger("livemigrate_instances")
LOG_FORMAT = '%(asctime)s %(levelname)-8s %(message)s'
DESCRIPTION = "Live migration tool to clear out a hypervisor"


def parse_args():
    # ensure environment has necessary items to authenticate
    for key in ['OS_TENANT_NAME', 'OS_USERNAME', 'OS_PASSWORD',
                'OS_AUTH_URL', 'OS_REGION_NAME']:
        if key not in os.environ.keys():
            LOG.exception("Your environment is missing '%s'")
    ap = argparse.ArgumentParser(description=DESCRIPTION)
    ap.add_argument('-d', '--debug', action='store_true',
                    default=False, help='Show debugging output')
    ap.add_argument('-q', '--quiet', action='store_true', default=False,
                    help='Only show error and warning messages')
    ap.add_argument('-n', '--noop', action='store_true', default=False,
                    help='Do not do any modifying operations (dry-run)')
    ap.add_argument('-m', '--migrate', action='store_true', default=False,
                    help='Migrate from one host to another')
    ap.add_argument('-r', '--recover', action='store_true', default=False,
                    help='Move hosts previously migrated back home')
    ap.add_argument('--source',
                    help='the FQDN of a hypervisor to move instances \
                    away from')
    ap.add_argument('--dest',
                    default=False,
                    help='the FQDN of a hypervisor to move instances \
                    to')
    ap.add_argument('--file', default='./results.json',
                    help='The file in which to store/retrieve the server list')
    ap.add_argument('--timeout', default=240,
                    help='How long to wait for migration to complete')
    ap.add_argument('--insecure', action='store_true', default=False,
                    help='Explicitly allow tool to perform '
                         '"insecure" SSL (https) requests. The server\'s '
                         'certificate will not be verified against any '
                         'certificate authorities. This option should be used '
                         'with caution.')
    return ap.parse_args()


def setup_logging(args):
    level = logging.INFO
    if args.quiet:
        level = logging.WARN
    if args.debug:
        level = logging.DEBUG
    logfilename = os.environ['HOME'] + '/livemigrations.log'
    logging.basicConfig(level=logging.DEBUG,
                        format=LOG_FORMAT,
                        filename=logfilename,
                        filemode='a')
    console = logging.StreamHandler()
    console.setLevel(level)
    LOG.addHandler(console)


def get_hypervisor_instances(args, nova):
    instance_list = []
    # check if the hypervisor exists and is unique
    hypervisor_id = nova.hypervisors.search(args.source)
    if len(hypervisor_id) != 1:
        LOG.exception("The hypervisor %s was either not found, "
                      "or found more than once",
                      args.source)
        raise SystemExit
    hyp_obj = nova.hypervisors.get(hypervisor_id[0])
    for instance in nova.servers.list(search_opts={'all_tenants': True}):
        inst_hyp = getattr(instance, 'OS-EXT-SRV-ATTR:hypervisor_hostname')
        if hyp_obj.hypervisor_hostname == inst_hyp:
            instance_list.append(instance)
    return instance_list


def migrate_instance(args, nova, keystone_client, instance, dest, timeout):
    result = {}
    start_hypervisor = getattr(instance, 'OS-EXT-SRV-ATTR:hypervisor_hostname')
    datestamp_start = datetime.datetime.now()
    try:
        tenant = keystone_client.tenants.find(id=instance.tenant_id).name
    except:
        tenant = 'unknown tenant'
    message = "Migrating %s (%s) - %s, from %s" % (instance.name,
                                                   instance.id,
                                                   tenant,
                                                   start_hypervisor)
    LOG.warn(message)
    if args.noop:
        check_result = {
            'message': 'noop',
            'new_hypervisor': start_hypervisor,
            'error': False
        }
    else:
        if instance.status == 'ACTIVE':
            if dest:
                instance.live_migrate(host=dest)
            else:
                instance.live_migrate()
            check_result = check_migration(instance, start_hypervisor, timeout)
        elif instance.status == 'SHUTOFF':
            instance.migrate()
            check_result = check_migration(instance, start_hypervisor, timeout)
        else:
            check_result = {
                'message': 'not moved',
                'new_hypervisor': start_hypervisor,
                'error': False
            }

    datestamp_end = datetime.datetime.now()
    duration = datestamp_end - datestamp_start
    result = {'instance': instance.id,
              'name': instance.name,
              'tenant': tenant,
              'state': instance.status,
              'message': check_result['message'],
              'start_hypervisor': start_hypervisor,
              'end_hypervisor': check_result['new_hypervisor'],
              'duration': "%.0f" % duration.total_seconds(),
              'error': check_result['error']}
    return result


def check_migration(instance, start_hypervisor, timeout):
    time.sleep(5)
    wait_time = 5
    error = False
    while wait_time < timeout:
        message = ''
        instance.get()
        new_hypervisor = getattr(instance,
                                 'OS-EXT-SRV-ATTR:hypervisor_hostname')
        if instance.status in ['ACTIVE', 'VERIFY_RESIZE']:
            if new_hypervisor == start_hypervisor:
                message = 'Instance did not move'
                error = True
            if new_hypervisor != start_hypervisor:
                message = 'Instance moved'
            break
        if instance.status == 'ERROR':
            message = 'Instance now in ERRROR state!'
            error = True
            break
        #TODO more checks here for status of instance after migration
        time.sleep(5)
        wait_time += 5
        sys.stdout.write("#")
        sys.stdout.flush()
    print
    check_result = {'new_hypervisor': new_hypervisor,
                    'message': message,
                    'error': error}
    return check_result


def migrate_away(args, nova, keystone_client, timeout):
    instances_to_migrate = get_hypervisor_instances(args, nova)
    if args.dest:
        dest_id = nova.hypervisors.search(args.dest)
        if len(dest_id) != 1:
            LOG.error("The hypervisor %s was either not found, or found "
                      "more than once",
                      args.source)
            raise SystemExit
        dest = nova.hypervisors.get(dest_id[0]).service['host']
    else:
        dest = False
    final_results = []
    for instance in instances_to_migrate:
        instance.get()
        result = migrate_instance(args, nova, keystone_client,
                                  instance, dest, timeout)
        LOG.warn("Instance %s moved from %s to %s, %s, "
                 "status is %s, took %ss",
                 result['name'],
                 result['start_hypervisor'],
                 result['end_hypervisor'],
                 result['message'],
                 result['state'],
                 result['duration'])
        if result['state'] == 'VERIFY_RESIZE':
            instance.confirm_resize()
            time.sleep(5)
            instance.get()
            result['state'] = instance.status
        final_results.append(result)
        if result['state'] not in ['ACTIVE', 'SHUTOFF', 'SUSPENDED']:
            break
        if result['error']:
            break
        if not args.noop:
            # ugh, a magic sleep to let things settle down
            time.sleep(30)
    # TODO(XP) this needs exception handling
    with open(args.file, 'w') as fp:
        json.dump(final_results, fp)
    fp.close()


def recover(args, nova, keystone_client, timeout):
    # TODO(XP) this needs exception handling
    with open(args.file, 'r') as fp:
        temp_locations = json.load(fp)
    fp.close()

    final_results = []
    for entry in temp_locations:
        if entry['end_hypervisor'] == entry['start_hypervisor']:
            print("Instance %s left alone" % entry['instance'])
        else:
            # set up instance, dest list
            instance = nova.servers.get(entry['instance'])
            dest = entry['start_hypervisor']
            result = migrate_instance(args,
                                      nova,
                                      keystone_client,
                                      instance,
                                      dest,
                                      timeout)
        final_results.append(result)
        # ugh, a magic sleep to let things settle down
        time.sleep(5)
    #pprint.pprint(final_results)


def main():
    args = parse_args()
    setup_logging(args)
    try:
        nova = client.Client(
            '2.0',
            os.environ['OS_USERNAME'],
            os.environ['OS_PASSWORD'],
            os.environ['OS_TENANT_NAME'],
            os.environ['OS_AUTH_URL'],
            region_name=os.environ['OS_REGION_NAME'])
    except Exception:
        raise
    try:
        keystone_client = ksclient.Client(
            username=os.environ['OS_USERNAME'],
            password=os.environ['OS_PASSWORD'],
            tenant_name=os.environ['OS_TENANT_NAME'],
            auth_url=os.environ['OS_AUTH_URL'],
            region_name=os.environ['OS_REGION_NAME'])
    except Exception:
        raise
    timeout = args.timeout
    if ((args.migrate and args.recover) or (args.migrate is False
                                            and args.recover is False)):
        LOG.exception("Please either migrate, or recover, but not both")
        raise SystemExit
    if args.migrate:
        if not args.source:
            LOG.exception("Must supply both source hypervisors")
            raise SystemExit
        migrate_away(args, nova, keystone_client, timeout)

    if args.recover:
        recover(args, nova, keystone_client, timeout)


if __name__ == '__main__':
    main()
