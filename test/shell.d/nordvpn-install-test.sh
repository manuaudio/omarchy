#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"

# Every command the installer reaches is a logger, so the run neither touches
# packages, services or groups nor reboots the machine.
for command in pacman sudo omarchy-pkg-add systemctl usermod omarchy-system-reboot; do
  cat >"$tmp_dir/bin/$command" <<SCRIPT
#!/bin/bash
printf '$command:%s\n' "\$*" >>"\$TEST_LOG"
SCRIPT
  chmod +x "$tmp_dir/bin/$command"
done

# The reboot prompt answers with TEST_GUM_STATUS: 1 declines, 0 accepts.
cat >"$tmp_dir/bin/gum" <<'SCRIPT'
#!/bin/bash
printf 'gum:%s\n' "$*" >>"$TEST_LOG"
exit "$TEST_GUM_STATUS"
SCRIPT
chmod +x "$tmp_dir/bin/gum"

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir/bin:$PATH"

run_install() {
  : >"$TEST_LOG"
  TEST_GUM_STATUS=$1 "$ROOT/bin/omarchy-install-service-nordvpn" >/dev/null
}

# The floating terminal reports any nonzero exit as a failure, so declining the
# optional reboot after a successful install must still exit 0.
status=0
run_install 1 || status=$?
(( status == 0 )) || fail "NordVPN install exits 0 when the reboot prompt is declined" "exit status: $status"
pass "NordVPN install exits 0 when the reboot prompt is declined"

! grep -q '^omarchy-system-reboot:' "$TEST_LOG" || fail "NordVPN install does not reboot when the prompt is declined"
pass "NordVPN install does not reboot when the prompt is declined"

status=0
run_install 0 || status=$?
(( status == 0 )) || fail "NordVPN install exits 0 when the reboot prompt is accepted" "exit status: $status"
grep -q '^omarchy-system-reboot:' "$TEST_LOG" || fail "NordVPN install reboots when the prompt is accepted" "$(cat "$TEST_LOG")"
pass "NordVPN install reboots when the prompt is accepted"
