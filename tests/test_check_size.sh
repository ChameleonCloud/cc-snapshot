#!/usr/bin/env bash

set -euo pipefail

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
    fail "Error: unable to find ${CC_SNAPSHOT} or it is not executable"
fi

# unique fake tar path for this run
uuid=$(uuidgen | cut -d- -f1)
fake_tar="/tmp/testing-cc-snapshot-${uuid}.tar"
trap 'rm -f "$fake_tar"' EXIT

### Testing check_size and prepare_tarball

dd if=/dev/zero of="$fake_tar" bs=1M count=10 status=none

output=$(echo yes |TESTING_SKIP_ROOT_CHECK=1 env \
  CC_SNAPSHOT_TAR_PATH="$fake_tar" \
  CC_SNAPSHOT_MAX_TARBALL_SIZE=5 \
  IGNORE_WARNING=false \
  DUMMY_STAGE=check_size \
  "$CC_SNAPSHOT" mytest 2>&1 || true )

if echo "$output" | grep -q "snapshot is too large"; then
  pass "check_size correctly detected large snapshot"
else
  fail "check_size did not detect large snapshot"
fi

