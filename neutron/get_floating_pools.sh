#!/usr/bin/env bash

# Copyright 2015 B1 Systems GmbH
#
# Author: Christian Berendt <berendt@b1-systems.de>
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# usage: ./get_floating_pools.sh [LOGFILE]

# Load an client environment script (openrc file) prior to running this script.

# description: This script will generate a list with all routers and assigned
#              external (gateway) and internal networks.

# example output:

# router_id;external_network_id;external_network_name;internal_network_id
# 16739053-2a05-46c2-b9b5-bdaf210466a7;f028f538-e95b-4b7b-86c3-b15fc0878648;EXTERNAL;d3ab88ac-5e6b-4d6b-b344-c40337cf16fe

set -x

output=${1:-reii.lst}

if [[ -e $output ]]; then
    echo "error: output file '$output' exists, please remove or move it first."
    exit
fi

echo "router_id;external_network_id;external_network_name;internal_network_id" | tee -a $output

for router in $(neutron router-list | grep enable_snat | awk '{ print $2 }'); do
    external=$(neutron router-show $router | grep external_gateway_info | awk -F\" '{ print $4 }')
    external_name=$(neutron net-show $external | grep name | awk -F\| '{ print $3 }' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    for subnet in $(neutron router-port-list $router | grep subnet | awk -F\" '{ print $4 }'); do
        network=$(neutron subnet-show $subnet | grep network_id | awk '{ print $4 }')
        if [[ $network != $external ]]; then
            echo "$router;$external;$external_name;$network" | tee -a $output
        fi
    done
done
