#!/usr/bin/env bash

set -euo pipefail

echo "Running cc-snapshot interface tests..."

fail() {
  echo "FAIL: $1"
  exit 1
}

pass() {
  echo "PASS: $1"
}

TEST_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC_SNAPSHOT="${TEST_SCRIPT_DIR}/../cc-snapshot"

if [[ ! -x "${CC_SNAPSHOT}" ]]; then
    echo "Error: unable to find ${CC_SNAPSHOT} or it is not executable"
    exit 1
fi

### Testing check_size and prepare_tarball

TESTING_SKIP_ROOT_CHECK=1 dd if=/dev/zero of=/tmp/fake.tar bs=1M count=10 status=none

# Run the check_size function and capture its output
output=$(echo yes |TESTING_SKIP_ROOT_CHECK=1 env \
  CC_SNAPSHOT_TAR_PATH=/tmp/fake.tar \
  CC_SNAPSHOT_MAX_TARBALL_SIZE=5 \
  IGNORE_WARNING=false \
  DUMMY_STAGE=check_size \
  "$CC_SNAPSHOT" mytest 2>&1)

if echo "$output" | grep -q "snapshot is too large"; then
  pass "check_size correctly detected large snapshot"
else
  fail "check_size did not detect large snapshot"
fi
#clean
TESTING_SKIP_ROOT_CHECK=1 rm -f /tmp/fake.tar

