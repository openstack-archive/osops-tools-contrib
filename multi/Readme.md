
# Multi folder

this folder contains scripts that are not related to a specific Openstack project.

## User info

Show the resources belonging to a user:

```
usage: user-info.py [-h] [-a] [-v] USERNAME

Show information (servers, volumes, networks, ...) for a user. Search in all
projects the user is member of, and optionally in all regions (-a).

positional arguments:
  USERNAME           username to search

optional arguments:
  -h, --help         show this help message and exit
  -a, --all-regions  query all regions
  -v, --verbose      verbose
```
