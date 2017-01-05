#!/usr/bin/env python
# -*- coding: utf-8 -*-

# Copyright 2016 OVH SAS
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


"""
The script checks how many neutron dhcp agents are handling one network and
spreads load of networks to be similar on all agents in infra.

"""

import argparse
import multiprocessing
import logging
import os
import random
import sys
import itertools

from neutronclient.v2_0 import client as neutronclient


OS_PREFIX = "OS_"
OS_REQUIRED_KEYS = [
    'username',
    'password',
    'tenant_name',
    'auth_url',
    'region_name']

MAX_ATTEMPTS = 3

DHCP_AGENT_TYPE = "DHCP agent"
HOST_ID = "binding:host_id"
RESERVED_DHCP_PORT = "reserved_dhcp_port"

_CLIENT = None
_CREDS = {}


def get_neutron_client():
    global _CLIENT
    if _CLIENT:
        return _CLIENT
    credentials = get_credentials()
    _CLIENT = neutronclient.Client(**credentials)
    return _CLIENT


def get_credentials():
    global _CREDS
    if _CREDS:
        return _CREDS
    for key in OS_REQUIRED_KEYS:
        env_key = OS_PREFIX + key.upper()
        value = os.environ.get(env_key)
        if not value:
            LOG.error("Missing %s in environment vars."
                     "Openstack environment vars should be loaded before "
                     "running this script", env_key)
            sys.exit(1)
        _CREDS[key] = value
    return _CREDS


def get_logger(verbose=False, debug=False, logfile=None, name=None):
    logger = logging.getLogger(name)
    formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
    loglevel = logging.ERROR
    if verbose:
        loglevel = logging.INFO
    if debug:
        loglevel = logging.DEBUG
    logger.setLevel(loglevel)

    if logfile:
        fh = logging.FileHandler(logfile)
        fh.setLevel(loglevel)
        fh.setFormatter(formatter)
        logger.addHandler(fh)
    else:
        ch = logging.StreamHandler()
        ch.setLevel(loglevel)
        ch.setFormatter(formatter)
        logger.addHandler(ch)
    return logger


def get_number_of_cores():
    try:
        return multiprocessing.cpu_count()
    except Exception:
        LOG.warning("Failed to determine number of cores in the system")
        return 1


def parse_args():

    def check_positive(value):
        ivalue = int(value)
        if ivalue <= 0:
             raise argparse.ArgumentTypeError(
                "%s is an invalid positive int value" % value)
        return ivalue

    program_description=("This script is working in two stages: \n"
                         "1. Checking number of DHCP agents for each \n"
                         "   network and removing some agents if there is \n"
                         "   too many assigned for network,\n"
                         "2. Calculating number of networks which every \n"
                         "   DHCP agent should handle. Balancing networks \n"
                         "   amont agents that each of them handles \n"
                         "   similar number of networks.\n\n"
                         "If --cold-restart is set, the script will do DHCP network \n"
                         "reassignment for all networks.")

    parser = argparse.ArgumentParser(
        description=program_description,
        formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("--workers", default=None, type=check_positive,
                        help=("Number of workers to do some operations "
                              "simultaneously (like removing dead agents) "
                              "from network. By default number of CPU "
                              "cores will be taken")),
    parser.add_argument("--max_agents_per_network", default=1, type=int,
                        help=("Maximum number of agents which should host "
                              "DHCP service for one network")),
    parser.add_argument("--remove-associations", action="store_true",
                        help="Remove all network to DHCP agent associations"),
    parser.add_argument("--add-associations", action="store_true",
                        help="Delegate all networks to DHCP agents by Round-Robin"),
    parser.add_argument("--cold-restart", action="store_true",
                        help="Remove all network to DHCP agent associations and "
                             "delegate all networks to DHCP agents by Round-Robin"),
    parser.add_argument("--debug", action="store_true",
                        help="Enable debug mode")
    parser.add_argument("--verbose", action="store_true",
                        help="Make script to be more verbose")
    parser.add_argument("--log-file", dest='logfile', default=None,
                        help="Log file path.")
    return parser.parse_args()


def remove_unneccessary_agents(number_of_workers):
    """Remove DHCP agents from handle DHCP service if there is more
    agents than set in MAX_AGENTS_PER_NETWORK.

    It performs clean for all networks with dhcp agents.
    """

    networks_agents = get_networks_agents(number_of_workers)
    if not networks_agents:
        return
    LOG.info("Cleaning networks from unneccessary DHCP agents")
    threads_pool = multiprocessing.Pool(processes=number_of_workers)
    threads_pool.map(remove_unneccessary_agents_for_network,
                     zip(networks_agents.keys(), networks_agents.values()))
    LOG.info("All networks cleaned")


def remove_unneccessary_agents_for_network(network_agents):
    """Remove DHCP agents from hosting DHCP service if there is more
    agents than set in MAX_AGENTS_PER_NETWORK.

    Example: network is assigned to 3 DHCP agents but should be only to
    one, the network will be deleted from two agents.
    Reserved_dhcp_ports will be deleted from this network as well.

    :param network_agents: tuple with network id as first element and
                           list of agents as second
    """

    network_id = network_agents[0]
    agents = network_agents[1]
    agents_to_stay = 0
    for agent in agents:
        agent_id = agent['id']
        agent_alive = agent['alive']
        if not agent_alive:
            LOG.info("Removing dead agent %(agent_id)s from network "
                     "%(network_id)s",
                     {'agent_id': agent_id, 'network_id': network_id})
            remove_network_from_agent(network_id, agent_id)
        else:
            if agents_to_stay < MAX_AGENTS_PER_NETWORK:
                LOG.debug("Agent %(agent_id)s will still handle DHCP for "
                          "network %(network_id)s",
                          {'agent_id': agent_id, 'network_id': network_id})
                agents_to_stay += 1
            else:
                LOG.info("Removing agent %(agent_id)s from network "
                         "%(network_id)s",
                         {'agent_id': agent_id, 'network_id': network_id})
                remove_network_from_agent(network_id, agent_id)
    remove_reserved_dhcp_ports(network_id)


def remove_reserved_dhcp_ports(network_id):
    """Remove reserved_dhcp_ports from network

    :param network_id: id of network to clean
    """

    client = get_neutron_client()
    try:
        ports = client.list_ports(network_id=network_id,
                                device_id=RESERVED_DHCP_PORT)
    except Exception as e:
        LOG.error("Failed to get list of reserved dhcp ports in "
                  "network %(network_id)s; Error: %(err)s",
                  {'network_id': network_id, 'err': e})
        return

    for port in ports['ports']:
        LOG.debug("Delete port %(port_id)s from network %(net_id)s",
                 {'port_id': port['id'], 'net_id': network_id})
        try:
            client.delete_port(port['id'])
        except Exception as e:
            LOG.error("Failed to remove reserved dhcp port %(port_id)s "
                      "from network %(network_id)s; Error: %(err)s",
                      {'port_id': port['id'],
                       'network_id': network_id,
                       'err': e})


def cold_restart(number_of_workers):
    """ Reassign all DHCP networks

    It performs remove all networks from all agents
    and then reassignment.
    """

    LOG.info("Performing cold restart procedure")
    remove_all_networks_from_all_agents(number_of_workers)
    associate_networks_to_agents()
    LOG.info("Cold restart done")


def associate_networks_to_agents():
    """Add DHCP networks associations

    It performs all networks to all agents
    association.
    """

    LOG.info("Performing network to agent associations")
    live_dhcp_agents, dead_dhcp_agents = get_dhcp_agents()
    networks_to_assign = get_list_of_networks_with_dhcp()

    if len(live_dhcp_agents) == 0:
        LOG.error("No live DHCP agents found")
        return
    if len(networks_to_assign) == 0:
        LOG.error("No DHCP networks found")
        return

    try:
        networks_left_to_assign = \
            assign_dhcp_networks_to_agents_rr(networks_to_assign,
                                              live_dhcp_agents)
        if networks_left_to_assign:
            LOG.info("Assignment for some networks failed. "
                     "Trying again." )
            result = \
                assign_dhcp_networks_to_agents_rr(networks_left_to_assign,
                                                  live_dhcp_agents)
            if result:
                raise Exception("Some networks needs to be "
                                "reassigned manually: ", str(result))
    except Exception as e:
       LOG.error("Error occured during associations: "
                 "%(err)s", {'err': e})

    LOG.info("Done network to agent associations")


def assign_dhcp_networks_to_agents_rr(networks_to_assign, dhcp_agents):
    """Assing given networks to given DHCP Agents by Round Robin

    :param networks_to_assign: list of networks to assign
    :dhcp_agents: list of dhcp agents

    :return networks_to_reassign: list of unassigned networks due failure
            or empty list if succeeded
    """

    LOG.info("Assigning networks to DHCP Agents by RoundRobin")
    number_of_networks_with_dhcp = len(networks_to_assign)
    number_of_live_dhcp_agents = len(dhcp_agents)
    agent_cycle = itertools.cycle(dhcp_agents)
    networks_to_reassign  = []

    for network_id in networks_to_assign:
        net, net_agents = get_agents_handled_network(network_id)
        agents_for_network = MAX_AGENTS_PER_NETWORK
        if net_agents:
                agents_for_network = MAX_AGENTS_PER_NETWORK - len(net_agents)
                if agents_for_network <= 0:
                    LOG.debug("Failed to assign network %(network_id)s to DHCP Agents "
                              "- network already assigned", {'network_id': network_id})
                continue
        for i in range (0, agents_for_network):
            agent_id = agent_cycle.next()
            attempt = 1
            assigned = False
            while attempt <= MAX_ATTEMPTS and assigned == False:
                if add_network_to_agent(network_id,agent_id):
                   assigned = True
                   continue
                else:
                   if attempt == MAX_ATTEMPTS:
                        networks_to_reassign.append(network_id)
                        LOG.error("Failed to assign network %(network_id)s to "
                                  "DHCP Agent %(agent_id)s",
                                  {'network_id': network_id, 'agent_id': agent_id})
                        break
                   else:
                        attempt += 1
    return networks_to_reassign


def balance_load_of_agents():
    """Main function to make balance of networks across DHCP agents

    It gets number of all agents from Neutron API and list of network_ids
    hanlded by each agent. Then it calculates how many networks should be
    handled by agent so all networks will be handled by alive agent(s).
    Finally it moves some networks from overloaded_agents to free_agents.
    """

    live_dhcp_agents, dead_dhcp_agents = get_dhcp_agents()
    dhcp_agents = dict(
        list(live_dhcp_agents.items()) + list(dead_dhcp_agents.items())
    )
    number_of_networks_with_dhcp = get_number_of_networks_with_dhcp(
        dhcp_agents)
    number_of_live_dhcp_agents = len(live_dhcp_agents)
    if number_of_live_dhcp_agents == 0:
        LOG.error("No live DHCP agents found")
        return
    # DHCP slot is network assigned to agent
    necessary_dhcp_slots = (
        number_of_networks_with_dhcp * MAX_AGENTS_PER_NETWORK)
    max_networks_per_agent = int(round(
        float(necessary_dhcp_slots) / float(number_of_live_dhcp_agents)
    ))
    overloaded_agents, full_agents, free_agents = split_agents(
        live_dhcp_agents, max_networks_per_agent)

    LOG.info("Overloaded agents: %s", overloaded_agents.keys())
    LOG.info("Full agents: %s", full_agents.keys())
    if len(free_agents) == 0:
        LOG.info("No any free agents found")
        return
    LOG.info("Free agents: %s", free_agents.keys())

    for overloaded_agent_id, networks in overloaded_agents.iteritems():
        networks_to_move = get_networks_to_move(overloaded_agent_id,
                                                max_networks_per_agent)
        LOG.info("Networks to move from agent %(agent_id)s: "
                 "%(networks)s",
                 {'agent_id': overloaded_agent_id,
                  'networks': networks_to_move})
        for network_id in networks_to_move:
            if len(free_agents) == 0:
                LOG.info("No any free agents found to move network %s",
                         network_id)
                return
            free_agents = move_network_to_new_agent(network_id,
                                                    overloaded_agent_id,
                                                    free_agents)


def get_dhcp_agents():
    """Get list of alive/dead DHCP agents and networks hosted by each agent

    :return agents: dict with ids of alive agents as keys and list of ids of
                    networks hostsed by agent
    :return agents: dict with ids of dead agents as keys and list of ids of
                    networks hosted by agent
    """

    client = get_neutron_client()
    live_agents = {}
    dead_agents = {}
    try:
        agents = client.list_agents(agent_type=DHCP_AGENT_TYPE)
    except Exception as e:
        LOG.error("Failed to get list of agents; Error: %s", e)
        return

    for agent in agents.get("agents", []):
        agent_networks = get_networks_on_agent(agent['id'])
        if agent.get('alive') == True:
            live_agents[agent['id']] = agent_networks
        else:
            dead_agents[agent['id']] = agent_networks
    return live_agents, dead_agents


def get_networks_agents(number_of_workers):
    """Get list of networks with ids of DHCP agents which hosts DHCP for net

    :return networks_agents: dict with network_id as key and list of ids of
                             DHCP agents which hosts this network as values
    """

    client = get_neutron_client()
    networks_agents = []
    try:
        networks = client.list_networks()
        networks_ids = [network['id'] for network in networks['networks']]
    except Exception as e:
        LOG.error("Failed to get list of networks; Error: %s", e)
        return
    threads_pool = multiprocessing.Pool(processes=number_of_workers)
    networks_agents = threads_pool.map(get_agents_handled_network,
                                       networks_ids)
    return dict(networks_agents)


def get_agents_handled_network(network_id):
    """Get list agents which handle network with given id

    :param network_id: id of network for which agents should be found

    :return: tuple with network_id as first value and list of ids of
             DHCP agents which hosts this network as second value
    """
    client = get_neutron_client()
    try:
        network_agents = client.list_dhcp_agent_hosting_networks(
            network_id)['agents']
        return (network_id, network_agents)

    except Exception as e:
        LOG.error("Failed to get list of DHCP agents for "
                  "network %(network_id)s; Error: %(err)s",
                  {'network_id': network_id, 'err': e})
        return (network_id, None)


def get_networks_on_agent(agent_id):
    """Get list of networks hosted on DHCP agent

    :param agent_id: id of agent to check
    """

    client = get_neutron_client()
    try:
        networks = client.list_networks_on_dhcp_agent(agent_id)['networks']
        return [network['id'] for network in networks]
    except Exception as e:
        LOG.error("Failed to get list of networks hosted by "
                  "agent %(agent_id)s; Error: %(err)s",
                  {'agent_id': agent_id, 'err': e})
        return []


def add_network_to_agent(network_id, agent_id):
    """Set network to be hosted by DHCP agent

    :param network_id: id of network which will be added to agent
    :param agent_id: id of agent which will host DHCP for network

    :return: True if network will be added to agent or Neutron will return
             error that agent is already hosting this network
             False if adding network to agent fails
    """

    client = get_neutron_client()
    LOG.debug("Adding network %(network_id)s to agent "
              "%(agent_id)s",
              {'network_id': network_id,
               'agent_id': agent_id})
    try:
        client.add_network_to_dhcp_agent(
            agent_id, {'network_id': network_id}
        )
    except neutronclient.common.exceptions.Conflict:
        LOG.warning("Network %(network_id)s is already hosted by "
                    "agent %(agent_id)s",
                    {'network_id': network_id,
                     'agent_id': agent_id})
    except Exception as e:
        LOG.error("Failed to add network %(network_id)s to "
                  "agent %(agent_id); Error: %(err)s",
                  {'network_id': network_id,
                   'agent_id': agent_id,
                   'err': e})
        return False
    return True


def remove_all_networks_from_all_agents(number_of_workers):
    """ Remove all DHCP networks from all DHCP agents

    :param agents: dict with agents and networks handled by those agents
    """

    LOG.info("Removing all networks from DHCP Agents")

    live_dhcp_agents, dead_dhcp_agents = get_dhcp_agents()
    dhcp_agents = dict(
        list(live_dhcp_agents.items()) + list(dead_dhcp_agents.items())
    )
    threads_pool = multiprocessing.Pool(processes=number_of_workers)

    nets = []
    for agent_id, networks in dhcp_agents.iteritems():
        if len(networks) > 0:
           nets.extend(networks)
           threads_pool.map(remove_network_from_agent_wrapper,
                            itertools.izip(networks,itertools.repeat(agent_id)))
    threads_pool.map(remove_reserved_dhcp_ports,
                     set(nets))
    LOG.info("All DHCP Agents cleaned")


def remove_network_from_agent_wrapper(args):
    """ Wrapper for function remove_network_from_agent
    """

    remove_network_from_agent(*args)


def remove_network_from_agent(network_id, agent_id):
    """Remove network from DHCP agent

    :param network_id: id of network which will be removed from agent
    :param agent_id: id of agent which to remove
    """

    LOG.debug("Removing network %(network_id)s from agent: %(agent_id)s",
             {'network_id': network_id, 'agent_id': agent_id})

    client = get_neutron_client()
    try:
        client.remove_network_from_dhcp_agent(agent_id, network_id)
    except Exception as e:
        LOG.error("Failed to remove network %(network_id)s from "
                  "agent %(agent_id)s; Error: %(err)s",
                  {'network_id': network_id,
                   'agent_id': agent_id,
                   'err': e})


def get_networks_to_move(agent_id, max_networks_on_agent):
    """Get list of networks which should be moved to other DHCP agents

    :param agent_id: id of agent from which networks should be moved
    :param max_networks_on_agent: max number of networks which agent should
                                  handle
    """

    networks_on_agent = get_networks_on_agent(agent_id)
    number_of_networks_to_move = len(networks_on_agent) - max_networks_on_agent
    return random.sample(networks_on_agent, number_of_networks_to_move)


def move_network_to_new_agent(network_id, old_agent_id, agents):
    """Move network from one DHCP agent to another one

    If adding to new agent will success then network will be also removed from
    old agent.

    :param network_id: id of network to move
    :param old_agent_id: id of existing agent which handles network
    :param: agents: list of agents from which new agent will be choosen

    :return agents: list of agents with updated list of networks for agents
    """
    attempt = 1
    while attempt <= MAX_ATTEMPTS:
        agent_id = random.choice(agents.keys())
        add_network_result = add_network_to_agent(
            network_id, agent_id)
        if add_network_result:
            agents[agent_id] = get_networks_on_agent(agent_id)
            remove_network_from_agent(network_id, old_agent_id)
            return agents
        else:
            attempt += 1
    return agents


def get_number_of_networks_with_dhcp(agents):
    """Get overall number of networks handled by at least one dhcp agent

    :param: dict with agents and networks handled by thoses agents

    :return: number of unique networks hosted on dhcp agents
    """

    networks = []
    for agent_networks in agents.values():
        networks += agent_networks
    return len(set(networks))


def get_list_of_networks_with_dhcp():
    """Get list of networks with enabled DHCP Agents

    :return: List of unique network_id
    """

    networks = []
    client = get_neutron_client()
    try:
        subnets = client.list_subnets(enable_dhcp=True)
        networks = [subnet['network_id'] for subnet in subnets.get("subnets", [])]
    except Exception as e:
        LOG.error("Failed to get list of networks with enable"
                  "dhcp, Error: %(err)s", {'err': e})
    return list(set(networks))


def split_agents(agents, max_networks_on_agent):
    """Divide list of agents into groups: overloaded, full and free

    Overloaded agent means that it hosts more networks than
        max_networks_on_agent,
    Full agent means that it hosts exactly max_networks_on_agent of networks,
    Free agent means that it hosts fewer networks than max_networks_on_agent
        so there is place for other networks on such agent

    :param agents: dict with agent_ids and list of networks hosted by each
                   agent
    :param max_networks_on_agent: max number of networks which can be hosted
                                  on agent

    :returns overloaded, full, free: dicts with agent_ids and lists of
                                     networks handled by each agent
    """

    overloaded = {}
    full = {}
    free = {}
    for agent, networks in agents.iteritems():
        agent_networks = len(networks)
        if agent_networks > max_networks_on_agent:
            overloaded[agent] = networks
        elif agent_networks == max_networks_on_agent:
            full[agent] = networks
        else:
            free[agent] = networks
    return overloaded, full, free


if __name__ == '__main__':
    global MAX_AGENTS_PER_NETWORK
    args = parse_args()
    # If debug is set to True then logger name is not set so root logger will
    # be used and also messages from neutronclient will be logged
    logger_name = None if args.debug else "dhcp_agents_balancer"
    LOG = get_logger(args.verbose, args.debug, args.logfile, logger_name)

    number_of_workers = args.workers or get_number_of_cores()
    MAX_AGENTS_PER_NETWORK = args.max_agents_per_network

    if args.cold_restart:
        cold_restart(number_of_workers)
    elif args.add_associations and args.remove_associations:
        cold_restart(number_of_workers)
    elif args.add_associations:
        associate_networks_to_agents()
    elif args.remove_associations:
        remove_all_networks_from_all_agents(number_of_workers)
    else:
        remove_unneccessary_agents(number_of_workers)
        balance_load_of_agents()
