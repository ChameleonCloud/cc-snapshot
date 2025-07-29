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
    "skipping vendordata & glance connectivity checks"
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

# Start of custom source path tests
TESTDIR=$(mktemp -d /tmp/cc_test.XXXXXX)

export CC_SNAPSHOT_TAR_PATH=$(mktemp "${PWD}/snapshot.XXXXXX.tar")
DEFAULT_TAR="$CC_SNAPSHOT_TAR_PATH"

[[ "$TESTDIR"  == /tmp/cc_test.* ]] || { echo "Unsafe TESTDIR: $TESTDIR"; exit 1; }
[[ "$DEFAULT_TAR" == "${PWD}/snapshot."*".tar" ]] || { echo "Unsafe snapshot path: $DEFAULT_TAR"; exit 1; }

cleanup() {
  rm -rf "$TESTDIR"
  rm -f   "$DEFAULT_TAR"
  echo "Deleted directories for test"
}
#trap will make sure to run cleanup before exiting
trap cleanup EXIT

mkdir -p "$TESTDIR/src/subdir"
echo hello > "$TESTDIR/src/file1.txt"
echo world > "$TESTDIR/src/subdir/file2.txt"
echo remove_me > "$TESTDIR/src/remove_me.txt"

#echo "testing custom path error on github"
#$TESTING_SKIP_ROOT_CHECK=1 "$CC_SNAPSHOT" -u -s "$TESTDIR/src" mytest
#echo "return :$?"

#Test 5: basic directory snapshot
if output=$(TESTING_SKIP_ROOT_CHECK=1 "$CC_SNAPSHOT" -u -s "$TESTDIR/src" mytest 2>&1); then
  pass "CC-Snapshot returned 0 for basic directory snapshot"
else
  echo "$output"
  fail "CC-Snapshot returned non-zero exit code for basic directory snapshot"
fi

# Verify directory created
if [[ "$output" != *"Tarball of $TESTDIR/src is ready at $DEFAULT_TAR"* ]]; then
  fail "Missing success message for $DEFAULT_TAR"
fi

# Verify the tarball exists
if [[ ! -s "$DEFAULT_TAR" ]]; then
  fail "Expected tarball $DEFAULT_TAR to exist and be non-zero size"
fi
pass "Basic tarball created at $DEFAULT_TAR"

# -------Start comparing all contents-------
diff \
  <(
    # list all file/dir under source but skip the "." itself
    cd "$TESTDIR/src" && \
    find . -mindepth 1 | \
    # Normalize path: drops any leading ./ and removes last slashes from directory names
      sed 's|^\./||; s|/$||' | \
    # puts in alphabetical order
      sort
  ) \
  <(
    # list every file/dir in the tarball
    tar -tf "$DEFAULT_TAR" | \
      # Normalize path: drop "./" prefix and "/" suffix
      sed 's|^\./||; s|/$||' | \
      # remove any blank line 
      grep -v '^$' | \
      # sort in alphabetical order for compresion 
      sort
  ) || fail "Contents mismatch for basic snapshot"

# the lists matched exactly
pass "Basic tarball content matches source directory"

# -------End of compresion-------

rm -f "$DEFAULT_TAR"

# Test 6: test -e fage
if output=$(TESTING_SKIP_ROOT_CHECK=1 "$CC_SNAPSHOT" -u -s $TESTDIR/src -e $TESTDIR/src/remove_me.txt exclude_test 2>&1); then
	pass "CC-Snapshot returned 0 for exclusion snapshot (-e flag)"
else
  echo "$output"
  fail "CC-Snapshot returned non-zero exit code for exclusion snapshot (-e flag)"
fi

# Verify creation message for exclusion
if [[ "$output" != *"Tarball of $TESTDIR/src is ready at $DEFAULT_TAR"* ]]; then
  fail "Missing success message for exclusion snapshot"
fi

# Verify the tarball exists
if [[ ! -s "$DEFAULT_TAR" ]]; then
  fail "Expected tarball $DEFAULT_TAR to exist and be non-zero size"
fi
pass "Exclusion tarball created at $DEFAULT_TAR"

# Ensure 'remove_me.txt' is not present
if tar -tf "$DEFAULT_TAR" | grep -q "remove_me.txt"; then
  fail "Excluded file 'remove_me.txt' found in tarball"
fi
pass "Excluded file correctly omitted"

# Validate only keep files present
EXPECTED=$(printf "file1.txt\nsubdir\nsubdir/file2.txt\n" | sort)
ACTUAL=$(tar -tf "$DEFAULT_TAR" | sed 's|^\./||; s|/$||' \
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

echo "All applicable interface tests passed."
