#!/usr/bin/env bash

set -euo pipefail

# To make this into a unit test of bash, we need to extract only the provenance block from cc-snapshot (which lives between markers)
PROVENANCE_SNIPPET=$(awk '/###### Get provenance properties ######/{flag=1;next}/###### Get provenance properties end ######/{flag=0}flag' cc-snapshot)

echo "Running provenance tests..."

run_case() {
  local json="$1"
  local tmp
  tmp=$(mktemp)
  echo "$json" > "$tmp"

  # Set up environment and execute just the snippet
  PROVENANCE_FILE="$tmp" PROVENANCE_PROPERTIES='' bash -c "$PROVENANCE_SNIPPET; echo \"\$PROVENANCE_PROPERTIES\""

  rm -f "$tmp"
}

assert_contains() {
  [[ "$2" == *"$1"* ]] || { echo "FAIL: expected '$1' in '$2'"; exit 1; }
}
assert_not_contains() {
  [[ "$2" != *"$1"* ]] || { echo "FAIL: did not expect '$1' in '$2'"; exit 1; }
}

out1=$(run_case '{"foo":"bar","build-distro":"ubuntu"}')
assert_contains provenance-foo=bar "$out1"
assert_contains build-distro=ubuntu "$out1"
echo "PASSED: No chameleon-supported provenance field"

out2=$(run_case '{"foo":"bar","chameleon-supported":"true","build-release":"noble"}')
assert_contains provenance-foo=bar "$out2"
assert_contains build-release=noble "$out2"
assert_not_contains chameleon-supported "$out2"
echo "PASSED: Skip chameleon-supported provenance field"

echo "All tests passed!"
