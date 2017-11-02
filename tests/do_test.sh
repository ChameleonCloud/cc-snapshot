#!/bin/bash

# This builds the environment then calls the Python script. As much as
# reasonable here in source control, rather than in the Jenkins config.

# Envvars that need setting:
# * All the OS_ vars (load an RC file)
# * KEY_FILE: location of an SSH private key associated with the "default"
#             key name on the infrastructure
# * IMAGE: ID/name of an image to test the snapshot on (probably should check
#          both...later)

set -o errexit

# my dev machine doesn't accept python3.6, but IUS only installed python3.6
# could symlink it on Jenkins, but this is maybe less disruptive.
if command -v python3 >/dev/null 2>&1
then
  PY3=python3
else
  PY3=python3.6
fi

$PY3 -m venv venv3
source venv3/bin/activate

set -o xtrace

python --version

pip --version
pip install --upgrade pip > pip.log
pip --version
pip install -r requirements.txt >> pip.log

pip freeze | grep hammers # hammers version (master branch, so somewhat volatile)

KEY_NAME=${KEY_NAME:-default}
# check the keypair exists (TODO: check the fingerprints match the $KEY_FILE)
nova keypair-show $KEY_NAME > /dev/null

python tests.py \
  --image=$IMAGE \
  --key-name=$KEY_NAME \
  --key-file=$KEY_FILE \
  --verbose \
  --no-clean
