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

rm -f /home/cc/Z-cc-snapshot/tests/mytest.tar
rm -f /home/cc/Z-cc-snapshot/tests/exclude_test.tar
rm -rf /tmp/cc_test

#prepare a single test directory with files
mkdir -p /tmp/cc_test/src/subdir
echo "hello" > /tmp/cc_test/src/file1.txt
echo "world" > /tmp/cc_test/src/subdir/file2.txt
echo "remove_me" > /tmp/cc_test/src/remove_me.txt

#Test 5: basic directory snapshot
if output=$(TESTING_SKIP_ROOT_CHECK=1 "$CC_SNAPSHOT" -u -s /tmp/cc_test/src mytest 2>&1); then
  pass "running basic directory snapshot"
else
  echo "$output"
  fail "cc-snapshot failed for basic snapshot"
fi

#verify directory created
if [[ "$output" != *"Tarball of /tmp/cc_test/src is ready at"* ]]; then
  fail "Missing success message for basic snapshot"
fi

TARFILE_BASIC="/home/cc/Z-cc-snapshot/tests/mytest.tar"
#verify the tarball exists
if [[ ! -s "$TARFILE_BASIC" ]]; then
  fail "Expected tarball $TARFILE_BASIC to exist and be non-zero size"
fi
pass "Basic tarball created at $TARFILE_BASIC"

#Compare all contents (including removed file)
diff \
  <(cd /tmp/cc_test/src && find . -mindepth 1 | sed 's|^\./||; s|/$||' | sort) \
  <(tar -tf "$TARFILE_BASIC" | sed 's|^\./||; s|/$||' | grep -v '^$' | sort) \
  || fail "Contents mismatch for basic snapshot"
pass "Basic tarball content matches source directory"

rm -f "$TARFILE_BASIC"

# Test 6: test -e fage
if output=$(TESTING_SKIP_ROOT_CHECK=1 "$CC_SNAPSHOT" -u -s /tmp/cc_test/src -e /tmp/cc_test/src/remove_me.txt exclude_test 2>&1); then
  pass "running basic directory snapshot with -e flag"
else
  echo "$output"
  fail "cc-snapshot failed for exclusion snapshot"
fi

#verify creation message for exclusion
if [[ "$output" != *"Tarball of /tmp/cc_test/src is ready at"* ]]; then
  fail "Missing success message for exclusion snapshot"
fi

TARFILE_EXCL="/home/cc/Z-cc-snapshot/tests/exclude_test.tar"
#Verify the tarball exists
if [[ ! -s "$TARFILE_EXCL" ]]; then
  fail "Expected tarball $TARFILE_EXCL to exist and be non-zero size"
fi
pass "Exclusion tarball created at $TARFILE_EXCL"

#Ensure 'remove_me.txt' is not present
if tar -tf "$TARFILE_EXCL" | grep -q "remove_me.txt"; then
  fail "Excluded file 'remove_me.txt' found in tarball"
fi
pass "Excluded file correctly omitted"

#Validate only keep files present
EXPECTED=$(printf "file1.txt\nsubdir\nsubdir/file2.txt\n" | sort)
ACTUAL=$(tar -tf "$TARFILE_EXCL" | sed 's|^\./||; s|/$||' \
    | grep -v '^$' \
    | sort )
if [[ "$EXPECTED" != "$ACTUAL" ]]; then
  echo "Expected files:" >&2
  echo "$EXPECTED" >&2
  echo "Actual files:" >&2
  echo "$ACTUAL" >&2
  fail "Unexpected entries in exclusion tarball"
fi
pass "Exclusion tarball content matches expected"

# Cleanup
rm -rf /tmp/cc_test
rm -f /home/cc/Z-cc-snapshot/tests/mytest.tar /home/cc/Z-cc-snapshot/tests/exclude_test.tar

echo "All applicable interface tests passed."
