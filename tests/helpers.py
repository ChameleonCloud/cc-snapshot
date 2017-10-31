import datetime
import os
import time

import paramiko


NEUTRON_ENDPOINT_FILTER = {
    'service_type': 'network',
    'interface': 'public',
}


def get_net(session):
    '''Find a shared internal network to use.'''
    resp = session.get('/v2.0/networks', endpoint_filter=NEUTRON_ENDPOINT_FILTER)
    networks = resp.json()['networks']
    for net in networks:
        if net['shared'] and not net['router:external']:
            return net
    raise RuntimeError("didn't find a good network to use from among:\n{}".format(networks))


def now():
    return datetime.datetime.now().isoformat()


def parse_line(line):
    parts = [part.strip() for part in line.strip('|').split('|', 1)]
    return parts


def wait_for_ssh(host, private_key_file, verbose=False, attempts=20, backoff_time=15, raise_error=True):
    for i in range(attempts):
        if verbose:
            print("Trying to connect to {} ({}/{})... ".format(host, i, attempts), end='')

        try:
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(host, username='cc', key_filename=private_key_file)
            if verbose:
                print("Connected to %s" % host)
            break
        except paramiko.AuthenticationException:
            if verbose:
                # sshd might be starting/cloud-init hasn't loaded keys yet?
                print("Authentication failed when connecting to {}".format(host))
            time.sleep(backoff_time)
        except Exception as e:
            if verbose:
                print("Could not SSH to {}, waiting for it to start ({})"
                      .format(host, e))
            time.sleep(backoff_time)

    # If we could not connect within time limit
    else:
        msg = "Could not connect to {}. Giving up".format(host)
        if raise_error:
            raise RuntimeError(msg)
        else:
            print(msg)
            return None

    return ssh


class ModSFTPClient(paramiko.SFTPClient):
    # https://stackoverflow.com/a/19974994/194586
    def put_dir(self, source, target):
        ''' Uploads the contents of the source directory to the target path. The
            target directory needs to exists. All subdirectories in source are
            created under target.
        '''
        for item in os.listdir(source):
            if os.path.isfile(os.path.join(source, item)):
                self.put(os.path.join(source, item), '%s/%s' % (target, item))
            else:
                self.mkdir('%s/%s' % (target, item), ignore_existing=True)
                self.put_dir(os.path.join(source, item), '%s/%s' % (target, item))

    def mkdir(self, path, mode=511, ignore_existing=False):
        ''' Augments mkdir by adding an option to not fail if the folder exists  '''
        try:
            super().mkdir(path, mode)
        except IOError:
            if ignore_existing:
                pass
            else:
                raise
