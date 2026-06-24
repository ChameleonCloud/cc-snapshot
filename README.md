# cc-snapshot

cc-snapshot takes snapshots of baremetal instances on the [Chameleon testbed](https://www.chameleoncloud.org).

## Dependencies

The script requires the following dependencies:

* Ubuntu or CentOS system
* Baremetal instance

## Usage

**Use this script from a Chameleon baremetal instance**. cc-snapshot uploads the snapshot via the OpenStack CLI, so you need OpenStack credentials available in the environment first. We recommend [ccauth](https://github.com/ChameleonCloud/ccauth).

Once you have auth configured for your environment and you log into the instance, run cc-snapshot with the following command:

```
sudo -E cc-snapshot [snapshot_name]
```

`-E` is required so root can see `OS_CLOUD` and reuse your cached ccauth credentials.

You can optionally specify a snapshot name. If no argument is present, the snapshot name is set to the instance hostname followed by a universally unique identifier.

After a few minutes, a snapshot will be uploaded in the image repository of the instance's site.

## Troubleshooting

**`virt-customize: error: libguestfs error: lvs: lvm lvs --help: Invalid units specification`**

* Problem: the LVM2 package is incompatible with libguestfs (see https://bugzilla.redhat.com/show_bug.cgi?id=1475018)
* Resolution: update the lvm2 package. On CentOS:
    ```
    sudo yum makecache
    sudo yum update lvm2
    ```

## Supported Operating Systems

cc-snapshot supports the following operating systems:

### CentOS Distributions

- CentOS Linux
- CentOS Stream

### Ubuntu Distributions

- All Ubuntu distributions

**Note:** The script is also designed to work with non-UEFI boot installations of Ubuntu.
