'''PyTest tests for cc-snapshot'''
import datetime
import os
import secrets

import pytest

from ccmanage.auth import session_from_args
from ccmanage.lease import Lease
from ccmanage.server import ServerError

from helpers import get_net


class SnapshotProvingGround:
    '''
    Sets up a space to work.
    '''
    def __init__(self, name=None, instance_retries=3):
        self.launch_failures_left = instance_retries

        if name is None:
            name = os.environ.get('BUILD_TAG', 'snaptest-{}'.format(secrets.token_hex(nbytes=6)))
        self.name = name
        self.prefix = '' # customize later within test

        self.volatile_images = []

        self.session, self.rc = session_from_args(rc=True)
        self.lease = self._create_lease()
        self.instance = None

        self.nets = [get_net(self.session)['id']]

    def _create_lease(self):
        return Lease(
            keystone_session=self.session,
            name='test-lease-{}'.format(self.name),
            node_type='compute',
            length=datetime.timedelta(minutes=240),
            sequester=True,
            # _no_clean=args.no_clean,
        )

    def __enter__(self):
        self.lease.__enter__()
        print('started lease {}'.format(self.lease))

    def __exit__(self, exc_type, exc_value, traceback):
        self.lease.__exit__(exc_type, exc_value, traceback)

        for image in self.volatile_images:
            self.delete_image(image)

    def start_instance(self, image):
        while True:
            try:
                self.instance = self.lease.create_server(
                    name='{}{}{}'.format(self.prefix, '-' if self.prefix else '', self.name),
                    image=image,
                    key='default', # FIXME import from env/conf or something
                    net_ids=self.nets,
                )
                print('launching instance {}'.format(self.instance))
                self.instance.wait()
            except ServerError as e:
                print('failed to launch instance ({})'.format(e))
                self.launch_failures_left -= 1
                if self.launch_failures_left == 0:
                    raise RuntimeError('ran out of retries')
                else:
                    print('getting new node (retries left: {})'.format(self.launch_failures_left))
                self.lease.__exit__(self, type(e), e, None) # fake a crash, let it do the sequestering
                self.lease = self._create_lease()
                self.lease.__enter__()
                print('started (new) lease: {}'.format(self.lease))

        self.instance.associate_floating_ip()
        return self.instance

    def delete_image(self, image):
        pass

    def rebuild(self, image, fake=True):
        '''
        Rebuild the instance with *image*. If *fake* is True, it will delete
        the instance, wait a bit, then create a new one. If *false*, it will
        simply use Nova's rebuild option.
        '''
        pass


@pytest.fixture
def proving_ground():
    with SnapshotProvingGround() as spg:
        yield spg


def test_basic(proving_ground):
    pg = proving_ground
    pg.prefix = 'basic'

    pg.start_instance()

    print(pg.instance.status())
