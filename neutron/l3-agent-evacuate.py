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

# Author: Saverio Proto <saverio.proto@switch.ch>

"""
Example usage:
python l3-agent-evacuate.py --from-l3agent 19f59173-68eb-49e3-a078-10831935a8f7 --to-l3agent f00dddd0-b944-4eeb-80d1-fa0811725196
python l3-agent-evacuate.py --from-l3agent f00dddd0-b944-4eeb-80d1-fa0811725196 --to-l3agent 19f59173-68eb-49e3-a078-10831935a8f7
"""

import os
import sys
sys.path.append('../lib')

import argparse
import openstackapi
import keystoneclient
import time

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
    """
    Evacuate a neutron l3-agent
    """
    parser = argparse.ArgumentParser(
        description="Evacuate a neutron l3-agent")
    parser.add_argument('-f', '--from-l3agent', help='l3agent uuid', required=True)
    parser.add_argument('-t', '--to-l3agent', help='l3agent uuid', required=True)
    parser.add_argument('-r', '--router', help='specific router')
    parser.add_argument('-s', '--sleep', help='sleep interval in seconds')
    parser.add_argument('-l', '--limit', help='max number of routers to migrate')
    parser.add_argument('-v', '--verbose', help='verbose', action='store_true')
    args = parser.parse_args()

    # get OS_* environment variables
    os_auth_url = get_environ('OS_AUTH_URL', args.verbose)
    os_username = get_environ('OS_USERNAME', args.verbose)
    os_password = get_environ('OS_PASSWORD', args.verbose)
    os_tenant_name = get_environ('OS_TENANT_NAME', args.verbose)
    os_region_name = get_environ('OS_REGION_NAME', args.verbose)


    api = openstackapi.OpenstackAPI(os_auth_url, os_username, os_password, os_project_name=os_tenant_name)
    if args.limit:
        limit=int(args.limit)
    else:
        limit = 0

    #Validate agent's UUID
    validateargs(api, os_region_name, args.from_l3agent, args.to_l3agent, args.router, args.sleep)

    if args.router:
        moverouter(api, os_region_name, args.from_l3agent, args.to_l3agent, args.router)
    else:
        evacuate_l3_agent(api, os_region_name, args.from_l3agent, args.to_l3agent, limit, args.sleep)

def validateargs(api, region, from_agent, to_agent, router, sleep):
    neutron = api.neutron(region)
    l3_agents_uuids=[]
    routers_uuids=[]

    for agent in neutron.list_agents()['agents']:
        if agent['agent_type'] == u"L3 agent":
           l3_agents_uuids.append(agent['id'])

    for r in neutron.list_routers()['routers']:
        routers_uuids.append(r['id'])

    if from_agent not in l3_agents_uuids:
        print "%s not a valid agent" % from_agent
        sys.exit(1)

    if to_agent not in l3_agents_uuids:
        print "%s not a valid agent" % to_agent
        sys.exit(1)

    if router:
        if router not in routers_uuids:
            print "%s not a valid router" % router
            sys.exit(1)
        if neutron.list_l3_agent_hosting_routers(router)['agents'][0]['id'] != from_agent:
            print "Wrong from_agent for specified router"
            sys.exit(1)

    if sleep < 0:
        print "Need to have non-negative amount of sleep!"

def moverouter(api, region, from_agent, to_agent, router):
    neutron = api.neutron(region)
    r_id = {'router_id': router}
    print "Removing router %s" % router
    neutron.remove_router_from_l3_agent(from_agent, router)
    print "Adding   router %s" % router
    neutron.add_router_to_l3_agent(to_agent, r_id)

def evacuate_l3_agent(api, region, from_agent, to_agent, limit, sleep):
    """Evacuate"""
    neutron = api.neutron(region)
    routers = neutron.list_routers_on_l3_agent(from_agent)["routers"]

    #filter out from the list ha routers
    ha_false_routers=[]
    for r in routers:
        if not r["ha"]:
           ha_false_routers.append(r)

    if not len(ha_false_routers):
        print "Warning: l3 agent was already evacuated"
        sys.exit(1)
    if limit and (len(ha_false_routers) > limit):
        ha_false_routers = ha_false_routers[0:limit]
    print ("Starting ... Moving a router every %s seconds\n" % sleep)
    for r in ha_false_routers:
        r_id = {'router_id': r['id']}
        print "Removing router %s" % r['id']
        neutron.remove_router_from_l3_agent(from_agent, r['id'])
        print "Adding   router %s" % r['id']
        neutron.add_router_to_l3_agent(to_agent, r_id)
        time.sleep(float(sleep))



if __name__ == '__main__':
    main()
