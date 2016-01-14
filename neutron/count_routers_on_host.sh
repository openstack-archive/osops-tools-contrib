#!/bin/bash

#set -x

# count the number of routers per host
# optional argument of ACTIVE_ONLY -- which will count routers on active L3 agents only

echo "Router count per host. Gathering data. Be patient."

if [ "$1" == "ACTIVE_ONLY" ]; then
    AGENTS=$(neutron agent-list --column id --column agent_type --column host --format csv --quote minimal --column admin_state_up --column alive | grep ':-)' | grep True | grep L3 | cut -f1 -d',')
else
    AGENTS=$(neutron agent-list --column id --column agent_type --column host --format csv --quote minimal | grep L3 | cut -f1 -d',')
fi

for agent in ${AGENTS}; do
    COUNT=$(neutron router-list-on-l3-agent --format csv --quote minimal ${agent} | grep -v "id,name,external_gateway_info" | grep "," | wc -l)
    ROUTER_HOST=$(neutron agent-list --column id --column agent_type --column host --format csv --quote minimal | grep L3 | grep ${agent} | cut -f3 -d',' | tr -d '\r')
    echo "${ROUTER_HOST} (${agent}): ${COUNT}"
done
