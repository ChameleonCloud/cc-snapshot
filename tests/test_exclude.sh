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

# Ensure the script exists and is executable
if [[ ! -x "$CC_SNAPSHOT" ]]; then
    echo "Error: cannot find or execute $CC_SNAPSHOT"
    exit 1
fi

#clean previous test dir
rm -f /home/cc/Z-cc-snapshot/tests/mytest.tar
rm -f /home/cc/Z-cc-snapshot/tests/exclude_test.tar
rm -rf /tmp/cc_test

#prepare a single test directory with files
mkdir -p /tmp/cc_test/src/subdir
echo "hello" > /tmp/cc_test/src/file1.txt
echo "world" > /tmp/cc_test/src/subdir/file2.txt
echo "remove_me" > /tmp/cc_test/src/remove_me.txt

#Test 1: basic directory snapshot
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

# Test 2: test -e fage 
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
# Cleanup
rm -rf /tmp/cc_test
rm -f /home/cc/Z-cc-snapshot/tests/mytest.tar /home/cc/Z-cc-snapshot/tests/exclude_test.tar

echo "All interface tests passed!"
