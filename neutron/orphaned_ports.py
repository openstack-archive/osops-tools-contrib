#!/usr/bin/env python

import optparse
import MySQLdb
import MySQLdb.cursors
import gc

NEUTRONDBHOST='localhost'
NEUTRONDBPORT=3306
NEUTRONDBUSER='neutron'
NEUTRONDBPASS='password'
NEUTRONDBNAME='neutron'

KEYSTONEDBHOST='localhost'
KEYSTONEDBPORT=3306
KEYSTONEDBUSER='keystone'
KEYSTONEDBPASS='password'
KEYSTONEDBNAME='keystone'


def get_options():
    """ command-line options """

    usage = "usage: %prog [options]"
    OptionParser = optparse.OptionParser
    parser = OptionParser(usage)

    required = optparse.OptionGroup(parser, "Required")
    optional = optparse.OptionGroup(parser, "Optional")

    optional.add_option('--neutrondbhost', dest='NEUTRONDBHOST',
        action='store', type='string', default='localhost',
        help="Neutron database hostname/IP (default=localhost).")
    optional.add_option('--neutrondbport', dest='NEUTRONDBPORT',
        action='store', type='int', default=int(3306),
        help="Neutron database port (default=3306).")
    optional.add_option('--neutrondbuser', dest='NEUTRONDBUSER',
        action='store', type='string', default='neutron',
        help="Neutron database user (default=neutron).")
    optional.add_option('--neutrondbpass', dest='NEUTRONDBPASS',
        action='store', type='string', default='password',
        help="Neutron database password (default=password).")
    optional.add_option('--neutrondbname', dest='NEUTRONDBNAME',
        action='store', type='string', default='neutron',
        help="Neutron database name (default=neutron).")
    optional.add_option('--keystonedbhost', dest='KEYSTONEDBHOST',
        action='store', type='string', default='localhost',
        help="Keystone database host (default=localhost).")
    optional.add_option('--keystonedbport', dest='KEYSTONEDBPORT',
        action='store', type='int', default=int(3306),
        help="Keystone database port (default=3306).")
    optional.add_option('--keystonedbuser', dest='KEYSTONEDBUSER',
        action='store', type='string', default='keystone',
        help="Keystone database user (default=keystone).")
    optional.add_option('--keystonedbpass', dest='KEYSTONEDBPASS',
        action='store', type='string', default='password',
        help="Keystone database password (default=password).")
    optional.add_option('--keystonedbname', dest='KEYSTONEDBNAME',
        action='store', type='string', default='keystone',
        help="Keystone database name (default=keystone).")

    parser.add_option_group(required)
    parser.add_option_group(optional)
    options, args = parser.parse_args()

    return options


def get_db_conn(host, port, user, passwd, dbname):
    db = MySQLdb.connect(host=host, port=port, user=user, passwd=passwd, db=dbname, cursorclass=MySQLdb.cursors.DictCursor)
    return db.cursor()


def get_tenants_from_keystone(kcursor):
    query = "SELECT id from project"
    kcursor.execute(query)
    results = []
    for result in kcursor.fetchall():
        results.append(result['id'])
    return results


def get_ports_from_neutron(ncursor):
    query = """SELECT tenant_id, id
               from ports
               where device_owner != 'network:router_gateway' AND tenant_id != ''
            """
    ncursor.execute(query)
    return ncursor.fetchall()


def find_orphaned_ports(all_tenants, port_mappings):
    """port_mappings needs to be a dict of
       {'tenant_id': <tenant_id>,
        'id':        <port_uuid>}"""

    orphaned_ports = []
    for pair in port_mappings:
        if pair['tenant_id'] not in all_tenants:
            orphaned_ports.append(pair)

    return orphaned_ports


def main():

    options = get_options()

    # start with a clean slate
    gc.collect()
    neutrondb = get_db_conn(options.NEUTRONDBHOST, options.NEUTRONDBPORT, options.NEUTRONDBUSER, options.NEUTRONDBPASS, options.NEUTRONDBNAME)

    keystonedb = get_db_conn(options.KEYSTONEDBHOST, options.KEYSTONEDBPORT, options.KEYSTONEDBUSER, options.KEYSTONEDBPASS, options.KEYSTONEDBNAME)

    keystone_tenants = get_tenants_from_keystone(keystonedb)
    ports = get_ports_from_neutron(neutrondb)

    return find_orphaned_ports(all_tenants=keystone_tenants, port_mappings=ports)
    # cleanup any possibly hanging connections
    gc.collect()

if __name__ == "__main__":
    results = main()
    if results:
        print "### Orphaned neutron ports ###"
        for result in results:
            print "port_id=%s, tenant_id=%s" % (result['id'], result['tenant_id'])
