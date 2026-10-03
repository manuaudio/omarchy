#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/lspci" <<'SH'
#!/bin/bash
printf '%s\n' "${OMARCHY_TEST_LSPCI:-}"
SH

cat >"$mock_bin/omarchy-hw-nvidia-gsp" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$mock_bin/omarchy-hw-nvidia-without-gsp" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >>"$OMARCHY_TEST_PKG_LOG"
SH
chmod +x "$mock_bin"/*

run_lib32() {
  OMARCHY_TEST_LSPCI="$1" OMARCHY_TEST_PKG_LOG="$test_tmp/packages" PATH="$mock_bin:$PATH" \
    "$ROOT/bin/omarchy-install-gaming-gpu-lib32" >"$test_tmp/output" 2>&1
}

rm -f "$test_tmp/packages"
run_lib32 "00:02.0 VGA compatible controller: Red Hat, Inc. Virtio 1.0 GPU" ||
  fail "a GPU with no lib32 drivers to add succeeds" "$(cat "$test_tmp/output")"
[[ ! -e $test_tmp/packages ]] || fail "no packages are installed for an unsupported GPU"
pass "a GPU with no lib32 drivers to add lets the game installers continue"

rm -f "$test_tmp/packages"
run_lib32 "03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 31" ||
  fail "an AMD GPU installs its lib32 driver" "$(cat "$test_tmp/output")"
grep -qx 'lib32-vulkan-radeon' "$test_tmp/packages" || fail "an AMD GPU gets lib32-vulkan-radeon"
pass "an AMD GPU installs lib32-vulkan-radeon"
