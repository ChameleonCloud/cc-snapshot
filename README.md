# cc-snapshot

cc-snapshot takes snapshots of baremetal instances on the [Chameleon testbed](https://www.chameleoncloud.org).

## Dependencies

The script requires the following dependencies:

* Ubuntu or CentOS system
* Baremetal instance

## Usage

**Use this script from a Chameleon baremetal instance**. To snapshot a baremetal instance, when logged into the instance via SSH, run cc-snapshot with the following command:

```
sudo cc-snapshot [snapshot_name]
```

You can optionally specify a snapshot name. If no argument is present, the snapshot name is set to the instance hostname followed by a universally unique identifier.

cc-snapshot will ask for your Chameleon password, and after a few minutes, a snapshot will be uploaded in the image repository of the instance's site (UC or TACC).
