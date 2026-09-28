#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
printf '#!/bin/bash\n[[ $VOXTYPE_MISSING == 1 ]]\n' >"$tmp/bin/omarchy-cmd-missing"
printf '#!/bin/bash\necho "launch $*" >>"%s/calls"\n' "$tmp" >"$tmp/bin/omarchy-launch-floating-terminal-with-presentation"
printf '#!/bin/bash\necho restart >>"%s/calls"\n' "$tmp" >"$tmp/bin/omarchy-restart-shell"
chmod +x "$tmp/bin/"*

run_config() {
  : >"$tmp/calls"
  VOXTYPE_MISSING=$1 PATH="$tmp/bin:$PATH" bash "$ROOT/bin/omarchy-voxtype-config"
}

# The bar's Dictate indicator is always shown, so a click without Voxtype
# offers the install instead of failing with "voxtype: command not found".
run_config 1
[[ $(cat "$tmp/calls") == "launch omarchy-voxtype-install" ]] ||
  fail "Dictate offers the Voxtype install when Voxtype is missing" "$(cat "$tmp/calls")"
pass "Dictate offers the Voxtype install when Voxtype is missing"

run_config 0
[[ $(cat "$tmp/calls") == $'launch voxtype configure\nrestart' ]] ||
  fail "Dictate opens the Voxtype configuration when Voxtype is installed" "$(cat "$tmp/calls")"
pass "Dictate opens the Voxtype configuration when Voxtype is installed"
