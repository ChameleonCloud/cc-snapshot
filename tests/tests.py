import argparse
import datetime
import os
from pprint import pprint
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
    remote_env = {
        'OS_USERNAME': rc['OS_USERNAME'],
        'OS_PASSWORD': rc['OS_PASSWORD'],
    }
    # prompts = {
    #     'Please enter your Chameleon username: ': rc['OS_USERNAME'],
    #     'Please enter your Chameleon password: ': rc['OS_PASSWORD'],
    # }
    fab_settings = {
        'user': 'cc',
        'host_string': remote,
        'key_filename': key_file,
        'abort_on_prompts': True,
        'warn_only': True,

        # no security!
        'reject_unknown_hosts': False,
        'disable_known_hosts': True,
        # 'prompts': prompts,
    }

    # contrive passwords for debugging
    ccpass = secrets.token_hex(nbytes=128 // 8)
    ccapass = secrets.token_hex(nbytes=128 // 8)
    print('Debug Passwords:')
    print('{:>10s} {}'.format('cc', ccpass))
    print('{:>10s} {}'.format('ccadmin', ccapass))

    # test fast fail
    print('checking if it fails quickly if bad credentials passed')
    start = time.monotonic()
    with fapi.settings(**fab_settings), \
         fcm.cd(REMOTE_WORKSPACE), \
         fcm.shell_env(OS_USERNAME='wrong', OS_PASSWORD='wrong'):
        fapi.run('chmod +x cc-snapshot')

        out = fapi.sudo('./cc-snapshot')
    elapsed = time.monotonic() - start
    assert elapsed < 5
    assert out.return_code != 0
    assert 'check username' in out

    print('doing a real snapshot run...')
    with fapi.settings(**fab_settings), \
         fcm.cd(REMOTE_WORKSPACE), \
         fcm.shell_env(**remote_env):

        # debug passwords
        fapi.sudo("echo -e 'cc:{}\\nccadmin:{}' | chpasswd".format(ccpass, ccapass))

        # fapi.run('chmod +x cc-snapshot')
        out = fapi.sudo('./cc-snapshot')

    if out.return_code != 0:
        raise RuntimeError('snapshot returned non-zero!')

    print('snapshot finished!')
    lines = out.splitlines()
    ilines = iter(lines)
    for line in ilines:
        if parse_line(line) == ['Property', 'Value']:
            next(ilines) # consume the ---- line
            break

    image_info = {}
    for line in ilines:
        if '------------' in line: # end of table
            break
        try:
            key, value = parse_line(line)
        except TypeError:
            print('could not parse line: "{}"'.format(line))
            continue

        image_info[key] = value

    if not image_info:
        raise RuntimeError('could not parse image info!')

    pprint(image_info)

    return image_info


def test_instance_working(remote, key_file):
    '''Basic exercise of functionality to make sure things are OK'''


def test_simple(lease, session, rc, key_file, key_name, image='CC-CentOS7'):
    # create initial instance
    nets = [get_net(session)['id']]
    instance = lease.create_server(
        name='snapshotme-{}'.format(BUILD_TAG),
        key=key_name,
        image=image,
        net_ids=nets,
    )
    print('instance started: {}'.format(instance))
    instance.wait()
    instance.associate_floating_ip()
    ssh = wait_for_ssh(instance.ip, key_file, verbose=True)
    ssh.close()
    # time.sleep(10) # give it another second, some problems sudo'ing

    print('copying local working directory to target')
    copy_repo_to_remote(instance.ip, key_file)

    # do it
    print('running cc-snapshot')
    new_image = execute_snapshot(instance.ip, key_file, rc)

    # # see if the resulting image is any good
    print('recreating instance with image')
    if False: # rebuild...I think this is broken because it doesn't trigger cloud-init correctly?
        instance.server.rebuild(new_image['id'])
        instance.wait()
    else:
        instance.delete()
        time.sleep(30) # let it clean up
        instance = lease.create_server(
            name='didthiswork-{}'.format(BUILD_TAG),
            image=new_image['id'],
            net_ids=nets,
        )
        instance.wait()
        instance.associate_floating_ip()

    print('instance started (again): {}'.format(instance))

    ssh = wait_for_ssh(instance.ip, key_file, raise_error=False, verbose=True)
    # input('Press return to continue...')
    test_instance_working(instance.ip, key_file)

    print('image {} successfully snapshot!'.format(image))
    # input('Press return to continue...')
    instance.delete()


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument(
        '-i', '--image', action='append',
        help='Image (name or ID) to use. Can be specified multiple times. '
             'If none are provided, uses "CC-CentOS7"',
    )
    parser.add_argument(
        '--key-name', type=str, default='default',
        help='SSH keypair name on OS used to create an instance.'
    )
    parser.add_argument(
        '--key-file', type=str,
        default=os.environ.get('KEY_FILE', '~/.ssh/id_rsa'),
        help='Path to SSH key associated with the key-name. If not provided, '
             'falls back to envvar KEY_FILE then to the string "~/.ssh/id_rsa"',
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

    images = args.image
    if not images:
        images = ['CC-CentOS7', 'CC-Ubuntu16.04']
    if args.verbose:
        print('testing images: {}'.format(images))

    key_file = args.key_file
    key_file = os.path.expanduser(key_file)
    if args.verbose:
        print('key file: {}'.format(key_file))

    session, rc = session_from_args(args=args, rc=True)

    lease = Lease(
        keystone_session=session,
        name='test-lease-{}'.format(BUILD_TAG),
        length=datetime.timedelta(minutes=240),
        sequester=True,
        _no_clean=args.no_clean,
    )
    print(now(), 'Lease: {}'.format(lease))
    with lease:
        sleep = 0 # sleep between loops to let the instance get torn down
        for image in args.image:
            time.sleep(sleep)
            sleep = 30
            print('-'*80)
            print('Starting test with image "{}"'.format(image))
            test_simple(lease, session, rc, key_file, args.key_name, image=image)


if __name__ == '__main__':
    sys.exit(main())
