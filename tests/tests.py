import argparse
import datetime
import os
import secrets
import sys
import time

from ccmanage.auth import session_from_args, add_arguments
from ccmanage.lease import Lease
from fabric import api as fapi
#from fabric import network as fnet
#from fabric import state as fstate
from fabric import context_managers as fcm
import paramiko
import ulid

from helpers import now, wait_for_ssh, get_net, ModSFTPClient, parse_line


BUILD_TAG = os.environ.get('BUILD_TAG', 'cc-snap-{}'.format(ulid.ulid()))

_THIS_FILE = os.path.realpath(os.path.dirname(__file__))
PROJECT_ROOT = os.path.realpath(os.path.join(_THIS_FILE, os.path.pardir))

REMOTE_WORKSPACE = '/home/cc/snapshot-workspace/'


def copy_repo_to_remote(remote, keypath):
    key = paramiko.RSAKey.from_private_key_file(keypath)

    transport = paramiko.Transport((remote, 22))
    transport.connect(username='cc', pkey=key)

    sftp = ModSFTPClient.from_transport(transport)

    target_dir = REMOTE_WORKSPACE
    sftp.mkdir(target_dir)

    sftp.put_dir(PROJECT_ROOT, target_dir)


def execute_snapshot(remote, key_file, rc):
    '''Do the snapshot'''
    fab_settings = {
        'user': 'cc',
        'host_string': remote,
        'key_filename': key_file,
        'abort_on_prompts': True,
        'warn_only': True,

        # no security!
        'reject_unknown_hosts': False,
        'disable_known_hosts': True,
    }
    remote_env = {
        'OS_USERNAME': rc['OS_USERNAME'],
        'OS_PASSWORD': rc['OS_PASSWORD'],
    }

    # contrive passwords for debugging
    ccpass = secrets.token_hex(nbytes=128 // 8)
    ccapass = secrets.token_hex(nbytes=128 // 8)
    print('Debug Passwords:')
    print('{:>10s} {}'.format('cc', ccpass))
    print('{:>10s} {}'.format('ccadmin', ccapass))

    with fapi.settings(**fab_settings), \
         fcm.cd(REMOTE_WORKSPACE), \
         fcm.shell_env(**remote_env):

        # debug passwords
        fapi.sudo("echo -e 'cc:{}\\nccadmin:{}' | chpasswd".format(ccpass, ccapass))

        fapi.run('chmod +x cc-snapshot')
        out = fapi.sudo('./cc-snapshot')

    if out.return_code != 0:
        raise RuntimeError('snapshot returned non-zero!')

    lines = out.splitlines()
    ilines = iter(lines)
    for line in ilines:
        if parse_line(line) == ['Property', 'Value']:
            next(ilines) # consume the ---- line
            break

    image_info = {}
    for line in ilines:
        if '------------' in line:
            break
        try:
            key, value = parse_line(line)
        except TypeError:
            print('could not parse line: "{}"'.format(line))
            continue

        image_info[key] = value

    if not image_info:
        raise RuntimeError('could not parse image info!')

    return image_info


def test_instance_working(remote, key_file):
    '''Basic exercise of functionality to make sure things are OK'''


def test_simple(lease, session, rc, key_file, image='CC-CentOS7'):
    # create initial instance
    nets = [get_net(session)['id']]
    instance = lease.create_server(image=image, net_ids=nets)
    instance.wait()
    instance.associate_floating_ip()
    ssh = wait_for_ssh(instance.ip, key_file, verbose=True)
    ssh.close()
    # time.sleep(10) # give it another second, some problems sudo'ing

    # push code there
    copy_repo_to_remote(instance.ip, key_file)

    # do it
    new_image = execute_snapshot(instance.ip, key_file, rc)

    # # see if the resulting image is any good
    if False: # rebuild...I think this is broken because it doesn't trigger cloud-init correctly?
        instance.server.rebuild(new_image['id'])
        instance.wait()
    else:
        instance.delete()
        time.sleep(30) # let it clean up
        instance = lease.create_server(image=new_image['id'], net_ids=nets)
        instance.wait()
        instance.associate_floating_ip()

    ssh = wait_for_ssh(instance.ip, key_file, raise_error=False, verbose=True)
    # input('Press return to continue...')
    test_instance_working(instance.ip, key_file)
    # input('Press return to continue...')


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        '-i', '--image', type=str, default='CC-CentOS7',
        help='Image (name or ID) to use',
    )
    parser.add_argument(
        '-k', '--key-file', type=str,
        help='Path to SSH key. If not provided, falls back to envvar KEY_FILE '
             'then to the string "~/.ssh/id_rsa"',
        default=os.environ.get('KEY_FILE', '~/.ssh/id_rsa'),
    )
    parser.add_argument(
        '-n', '--no-clean', action='store_true',
        help='Don\'t clean up the lease on a crash (allows for debugging)',
    )
    parser.add_argument(
        '-v', '--verbose', action='store_true',
        help='Increase verbosity',
    )
    add_arguments(parser)

    args = parser.parse_args()

    key_file = args.key_file
    if args.verbose:
        print('key file: {}'.format(key_file))
    # if key_file is None:
    #     try:
    #         key_file = os.environ['KEY_FILE']
    #     except KeyError:
    #         print('Neither KEY_FILE set in environment nor --key-file option '
    #               'provided: one must be.', file=sys.stderr)
    #         return 1

    session, rc = session_from_args(args=args, rc=True)

    lease = Lease(
        keystone_session=session,
        name='test-{}'.format(BUILD_TAG),
        length=datetime.timedelta(minutes=240),
        sequester=True,
        _no_clean=args.no_clean,
    )
    print(now(), 'Lease: {}'.format(lease))
    with lease:
        test_simple(lease, session, rc, key_file, image=args.image)


if __name__ == '__main__':
    sys.exit(main())
