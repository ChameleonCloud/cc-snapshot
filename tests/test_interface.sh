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

CC_SNAPSHOT=../cc-snapshot

# Test 1: Help option (-h)
output=$(sudo "$CC_SNAPSHOT" --dummy -h 2>&1) || true
if [[ "$output" == *"usage:"* ]]; then
  pass "Help option (-h) shows usage"
else
  fail "Help option (-h) did not show usage"
fi

# Test 2: -e without folder
output=$(sudo "$CC_SNAPSHOT" -e 2>&1) && status=0 || status=$?
if [[ $status -ne 0 && "$output" == *"usage:"* ]]; then
  pass "-e without folder fails with error"
else
  fail "-e without folder did not fail as expected"
fi

#test 3: running with an invalid flag (-z)
output=$(sudo "$CC_SNAPSHOT" -z 2>&1) && status=0 || status=$?
if [[ $status -ne 0 && "$output" == *"usage:"* ]]; then
  pass "Invalid flag (-z) is handled with error"
else
  fail "Invalid flag (-z) did not trigger error as expected"
fi

# Test 4: -f suppresses warnings
#output=$(sudo "$CC_SNAPSHOT" -f test-snapshot 2>&1) && status=0 || status=$?
#if echo "$output" | grep -qi "warning"; then
#  fail "-f did not ignore warnings"
#else
#  pass "-f ignored warnings as expected"
#fi

#test 5: -y flage test 
#output=$(sudo "$CC_SNAPSHOT" -y 2>&1) || true
#if echo "$output" | grep -qi "y/n"; then
#  fail "With -y, script still prompted for confirmation"
#else
#  pass "With -y, script skipped confirmation as expected"
#fi

echo "All applicable interface tests passed."
