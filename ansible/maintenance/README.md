# Maintenace playbooks for administrating an OpenStack cloud

The playbooks in this ansible root perform (hopefully) zero-downtime rolling maintenance on certain kinds of OpenStack infrastructure hosts.

What these have in common is that a maintenance role is passed in as an ansible variable, and is included on each in that hostgroup.

There is an assumption that OpenStack administration credentials are present as environment variables. Be sure to source those in before execution.

maintenance_compute.yml
=======================

This playbook attempts to drain each compute host with an included python script.

## Example usage

`ansible-playbook -i hosts -e maintenace_role=stub playbooks/maintenace_compute.yml`
