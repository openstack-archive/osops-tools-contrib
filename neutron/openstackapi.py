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

# Author: Valery Tschopp <valery.tschopp@switch.ch>
# Date: 2016-07-05

import keystoneclient

from cinderclient.v2 import client as cinder_client
from glanceclient.v2 import client as glance_client
from keystoneauth1.identity import v3 as identity_v3
from keystoneauth1 import session
from keystoneclient.v3 import client as keystone_v3
from neutronclient.v2_0 import client as neutron_client
from novaclient import client as nova_client

class OpenstackAPI():
    """Openstack API clients

    Initialize all the necessary Openstack clients for all available region.
    """

    def __init__(self, os_auth_url, os_username, os_password, os_project_name,
                 domain_name='default',
                 user_domain_name='default',
                 project_domain_name='default'):
        # keystone_V3 client requires a /v3 auth url
        if '/v2.0' in os_auth_url:
            self.auth_url = os_auth_url.replace('/v2.0', '/v3')
        else:
            self.auth_url = os_auth_url

        _auth = identity_v3.Password(auth_url=self.auth_url,
                                    username=os_username,
                                    password=os_password,
                                    project_name=os_project_name,
                                    user_domain_name=user_domain_name,
                                    project_domain_name=project_domain_name)
        self._auth_session = session.Session(auth=_auth)
        self._keystone = keystone_v3.Client(session=self._auth_session)

        # all regions available
        self.all_region_names = []
        for region in self.keystone.regions.list():
            self.all_region_names.append(region.id)

        self._nova = {}
        self._cinder = {}
        self._neutron = {}
        self._glance = {}

    @property
    def keystone(self):
        """Get Keystone client"""
        return self._keystone

    def nova(self, region):
        """Get Nova client for the region."""
        if region not in self._nova:
            # Nova client lazy initialisation
            _nova = nova_client.Client('2',
                                       session=self._auth_session,
                                       region_name=region)
            self._nova[region] = _nova
        return self._nova[region]


    def cinder(self, region):
        """Get Cinder client for the region."""
        if region not in self._cinder:
            # Cinder client lazy initialisation
            _cinder = cinder_client.Client(session=self._auth_session,
                                           region_name=region)
            self._cinder[region] = _cinder
        return self._cinder[region]

    def neutron(self, region):
        """Get Neutron client for the region."""
        if region not in self._neutron:
            # Neutron client lazy initialisation
            _neutron = neutron_client.Client(session=self._auth_session,
                                             region_name=region)
            self._neutron[region] = _neutron
        return self._neutron[region]

    def glance(self, region):
        """Get Glance client for the region."""
        if region not in self._glance:
            # Glance client lazy initialisation
            _glance = glance_client.Client(session=self._auth_session,
                                           region_name=region)
            self._glance[region] = _glance
        return self._glance[region]

    def get_all_regions(self):
        """Get list of all region names"""
        return self.all_region_names

    def get_user(self, user_name_or_id):
        """Get a user by name or id"""
        user = None
        try:
            # try by name
            user = self._keystone.users.find(name=user_name_or_id)
        except keystoneclient.exceptions.NotFound as e:
            # try by ID
            user = self._keystone.users.get(user_name_or_id)
        return user

    def get_user_projects(self, user):
        """Get all user projects"""
        projects = self._keystone.projects.list(user=user)
        return projects

    def get_project(self, project_name_or_id):
        """Get a project by name or id"""
        project = None
        try:
            # try by name
            project = self._keystone.projects.find(name=project_name_or_id)
        except keystoneclient.exceptions.NotFound as e:
            # try by ID
            project = self._keystone.projects.get(project_name_or_id)
        return project

    def get_project_users(self, project):
        """Get all users in project"""
        assignments = self._keystone.role_assignments.list(project=project)
        user_ids = set()
        for assignment in assignments:
            if hasattr(assignment, 'user'):
                user_ids.add(assignment.user['id'])
        users = []
        for user_id in user_ids:
            users.append(self._keystone.users.get(user_id))
        return users

