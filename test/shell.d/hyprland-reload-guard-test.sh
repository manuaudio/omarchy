#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

run_root="$test_tmp/run-user"
state_dir="$test_tmp/state"
hyprctl_log="$test_tmp/hyprctl.log"
fake_hyprctl="$test_tmp/hyprctl"
signature="test-signature"
runtime_dir="$run_root/1000"

dead_signature="dead-signature"

mkdir -p "$runtime_dir/hypr/$signature" "$runtime_dir/hypr/$dead_signature"

cat >"$fake_hyprctl" <<'BASH'
#!/bin/bash

printf '%s\t%s\n' "$XDG_RUNTIME_DIR" "$*" >>"$FAKE_HYPRCTL_LOG"

case "$*" in
  *'--instance dead-signature '*)
    printf "Couldn't connect to %s/hypr/dead-signature/.socket.sock. (4)\n" "$XDG_RUNTIME_DIR"
    exit 4
    ;;
  *'getoption misc.disable_autoreload'*)
    printf '{"option":"misc.disable_autoreload","bool":%s,"set":true}\n' "${FAKE_DISABLE_AUTORELOAD:-false}"
    ;;
  *'getoption debug.suppress_errors'*)
    printf '{"option":"debug.suppress_errors","bool":%s,"set":true}\n' "${FAKE_SUPPRESS_ERRORS:-false}"
    ;;
  *)
    printf 'ok\n'
    ;;
esac
BASH
chmod 0755 "$fake_hyprctl"

FAKE_HYPRCTL_LOG="$hyprctl_log" \
  HYPRCTL="$fake_hyprctl" \
  OMARCHY_HYPRLAND_RELOAD_GUARD_RUN_ROOT="$run_root" \
  OMARCHY_HYPRLAND_RELOAD_GUARD_STATE_DIR="$state_dir" \
  "$ROOT/bin/omarchy-hyprland-reload-guard" pause 2>"$test_tmp/pause-stderr"

state_file="$state_dir/$signature"
[[ -f $state_file ]] || fail "reload guard stores Hyprland state on pause"
expected_state=$(printf '%s\tfalse\tfalse' "$runtime_dir")
grep -Fx "$expected_state" "$state_file" >/dev/null || fail "reload guard records previous Hyprland reload settings"
grep -F 'hl.config({ misc = { disable_autoreload = true }, debug = { suppress_errors = true } })' "$hyprctl_log" >/dev/null || fail "reload guard pauses autoreload with hyprctl eval"
pass "reload guard pauses live Hyprland reloads"

[[ ! -e $state_dir/$dead_signature ]] || fail "reload guard skips instances hyprctl cannot reach"
[[ ! -s $test_tmp/pause-stderr ]] || fail "reload guard pauses dead Hyprland instances quietly" "$(cat "$test_tmp/pause-stderr")"
pass "reload guard skips dead Hyprland instances quietly"

: >"$hyprctl_log"
FAKE_HYPRCTL_LOG="$hyprctl_log" \
  HYPRCTL="$fake_hyprctl" \
  OMARCHY_HYPRLAND_RELOAD_GUARD_RUN_ROOT="$run_root" \
  OMARCHY_HYPRLAND_RELOAD_GUARD_STATE_DIR="$state_dir" \
  "$ROOT/bin/omarchy-hyprland-reload-guard" resume

[[ ! -e $state_file ]] || fail "reload guard clears Hyprland state after resume"
grep -F -- '--instance test-signature reload' "$hyprctl_log" >/dev/null || fail "reload guard forces one Hyprland reload after package transaction"
grep -F 'hl.config({ misc = { disable_autoreload = false }, debug = { suppress_errors = false } })' "$hyprctl_log" >/dev/null || fail "reload guard restores previous Hyprland reload settings"
pass "reload guard resumes live Hyprland reloads"

# The modeless monitor recovery loop reloads on its own schedule, so it needs to
# ask whether a transaction is in flight.
rm -rf "$state_dir"
OMARCHY_HYPRLAND_RELOAD_GUARD_STATE_DIR="$state_dir" "$ROOT/bin/omarchy-hyprland-reload-guard" paused &&
  fail "reload guard reports itself unpaused before any transaction"

mkdir -p "$state_dir"
OMARCHY_HYPRLAND_RELOAD_GUARD_STATE_DIR="$state_dir" "$ROOT/bin/omarchy-hyprland-reload-guard" paused &&
  fail "an empty state directory is not a paused transaction"

touch "$state_dir/some-signature"
OMARCHY_HYPRLAND_RELOAD_GUARD_STATE_DIR="$state_dir" "$ROOT/bin/omarchy-hyprland-reload-guard" paused ||
  fail "reload guard reports itself paused during a transaction"
pass "reload guard reports whether a transaction is holding reloads"

# Hyprland re-runs bootstrap.lua and re-requires toggles.lua in the same Lua
# state on every reload, so their package.path entries must not pile up.
# `lua -` rather than bare `lua`: Lua 5.4 exits 0 on an error in a script it
# reads from a non-terminal stdin without the dash.
require_command lua
mkdir -p "$test_tmp/home"
HOME="$test_tmp/home" XDG_STATE_HOME="$test_tmp/home/.local/state" OMARCHY_PATH="$ROOT" lua - <<'LUA' ||
local noop = function() return function() end end
package.preload["default.hypr.require_all"] = function() return { files = function() end } end
package.preload["default.hypr.disabled-input-device"] = noop
package.preload["default.hypr.workspace-layouts"] = function() return true end

local original = package.path
local function reload()
  dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
  require("default.hypr.toggles")
end

reload()
local home, root = os.getenv("HOME"), os.getenv("OMARCHY_PATH")
local expected = home .. "/.local/state/omarchy/toggles/hypr/?.lua;"
  .. home .. "/.local/state/?.lua;"
  .. home .. "/.config/?.lua;"
  .. root .. "/?.lua;"
  .. original
assert(package.path == expected, "first load package.path: " .. package.path)

reload()
assert(package.path == expected, "second load package.path: " .. package.path)
reload()
assert(package.path == expected, "third load package.path: " .. package.path)
LUA
  fail "Hyprland reloads keep package.path stable"
pass "Hyprland reloads keep package.path stable"
