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

#Test if the path exist 
if [[ ! -x "${CC_SNAPSHOT}" ]]; then
    echo "Error: unable to find ${CC_SNAPSHOT} or it is not executable"
    exit 1
fi

# Test 1: Help option (-h)
output=$(TESTING_SKIP_ROOT_CHECK=1 "$CC_SNAPSHOT" -h 2>&1) || true
if [[ "$output" == *"usage:"* ]]; then
  pass "Help option (-h) shows usage"
else
  fail "Help option (-h) did not show usage"
fi

# Test 2: -e without folder
output=$(TESTING_SKIP_ROOT_CHECK=1 "$CC_SNAPSHOT" -e 2>&1) && status=0 || status=$?
if [[ $status -ne 0 && "$output" == *"usage:"* ]]; then
  pass "-e without folder fails with error"
else
  fail "-e without folder did not fail as expected"
fi

#Test 3: running with an invalid flag (-z)
output=$(TESTING_SKIP_ROOT_CHECK=1 "$CC_SNAPSHOT" -z 2>&1) && status=0 || status=$?
if [[ $status -ne 0 && "$output" == *"usage:"* ]]; then
  pass "Invalid flag (-z) is handled with error"
else
  fail "Invalid flag (-z) did not trigger error as expected"
fi

#Test 4: Dry-run does not error and prints each step
echo "testing dry_run"
TESTING_SKIP_ROOT_CHECK=1 "$CC_SNAPSHOT" -d mytest
echo "return :$?"
if output=$(TESTING_SKIP_ROOT_CHECK=1 "$CC_SNAPSHOT" -d mytest 2>&1); then
  if [[ $? -ne 0 ]]; then
    fail "Dry-run exited with error: $output"
  fi
  expected=(
    "tar --create"
    "check snapshot size"
    "apt-get install -yq libguestfs-tools"
    "apt-get -yq update"
    "apt-get install -yq kpartx"
    "would measure filesystem size"
    "guestfish"
    "virt-sysprep"
    "qemu-img convert"
    "openstack image create"
  )

  missing=0
  for pat in "${expected[@]}"; do
    if ! grep -q "\[DRY_RUN\].*${pat}" <<<"$output"; then 
      echo "Missing Dry-run for: $pat" >&2
      missing=$((missing+1))
    fi
  done

  if (( missing > 0 )); then 
    fail "Dry-run is missing $missing expected steps"
  else
    pass "Dry-run printed all ${#expected[@]} steps without error"
  fi
else
  fail "Dry-run exited with error: $output"
fi

echo "All applicable interface tests passed."
