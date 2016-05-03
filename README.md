# ChameleonSnapshotting

This repository contains a script in charge of snapshotting baremetal instances.

## Dependencies

The script requires the following dependencies:
* Ubuntu or CentOS system
* Baremetal instance

## Usage

**Use this script from a baremetal instance**. To snapshot a baremetal instance, simply run the script with the following command:

```
sudo bash cc-snapshot <snapshot_name>
```

It will ask for your Chameleon password, and after few minutes, a snapshot will be uploaded on the Glance corresponding to the instance's site (UC or TACC).
