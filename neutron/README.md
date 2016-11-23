# Neutron folder

this folder contains scripts that are related to Neutron

## L3 Agent Evacuate

Migrate away from a L3 Agent the Openstack routers

```
./l3-agent-evacuate.py --help
usage: l3-agent-evacuate.py [-h] [-f FROM_L3AGENT] [-t TO_L3AGENT] [-r ROUTER]
                            [-l LIMIT] [-v]

Evacuate a neutron l3-agent

optional arguments:
  -h, --help            show this help message and exit
  -f FROM_L3AGENT, --from-l3agent FROM_L3AGENT
                        l3agent uuid
  -t TO_L3AGENT, --to-l3agent TO_L3AGENT
                        l3agent uuid
  -r ROUTER, --router ROUTER
                        specific router
  -l LIMIT, --limit LIMIT
                        max number of routers to migrate
  -v, --verbose         verbose
```

First of all we should have clear in mind that when we create a router in
Openstack, that router is just a network namespace on one of the network nodes,
with name qrouter-<uuid>. For each namespace there is a qr (downstream) and a
qg (upstream) interface. In some situations an operation might want to migrate
away all the routers from a network node, to be able for example to reboot the
node without impacting the user traffic. The neutron component responsible for
creating the namespaces and cabling them with openvswitch is the l3 agent. You
can check the uuid of the l3 agents currently running with:

``` openstack network agent list ```

When you are running multiple l3 agents, if you create a new router Openstack
will schedule the namespace to be created on one of the available network
nodes. Given a specific router, with this command you can find out on which
network node the namespace has been created:
```
neutron l3-agent-list-hosting-router <router_uuid>
```

To list instead all the routers scheduled on a specific network node ```
neutron router-list-on-l3-agent <l3agent-uuid> ``` Using the neutron commands
`l3-agent-router-add` and `l3-agent-router-remove` is then possible to move a
router from a l3 agent to another one.

The tool `l3-agent-evacuate.py` will create a list of all the routers present
on the `from-agent` and will move 1 router every 10 seconds to the `to-agent`.
It is better to add a 10 seconds delay because Openvswitch has to make a lot of
operations when the namespace is created, and moving many routers at once will
cause openvswitch to blow up with unpredictable behavior.

The script has also a `--router` option if you want to migrate a specific
router, or a `--limit` option if you want to migrate just a few routers.

While migrating the routers, you can check (especially on the target l3-agent)
the openvswitch operations going on in `/var/log/syslog`.

