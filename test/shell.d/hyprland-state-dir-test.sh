#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home_dir="$tmpdir/home"
xdg_decoy="$tmpdir/xdg-state"
state_dir="$home_dir/.local/state/omarchy"
mkdir -p "$state_dir/toggles/hypr" "$state_dir/workspace-layouts" "$xdg_decoy"

# The bash writers (omarchy-hyprland-toggle, omarchy-hyprland-workspace-layout-toggle)
# always write under ~/.local/state, so the Lua readers must load from there even
# when XDG_STATE_HOME points somewhere else.
printf 'omarchy_test_toggle_loaded = true\n' >"$state_dir/toggles/hypr/test-flag.lua"
printf 'hl.workspace_rule({ workspace = "3", layout = "scrolling" })\n' >"$state_dir/workspace-layouts/3.lua"

HOME="$home_dir" XDG_STATE_HOME="$xdg_decoy" OMARCHY_PATH="$ROOT" lua - <<'LUA'
local rules = {}

hl = {
  device = function() end,
  workspace_rule = function(rule)
    table.insert(rules, rule)
  end,
}

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("default.hypr.toggles")
require("default.hypr.workspace-layouts")

assert(omarchy_test_toggle_loaded, "toggle flag from ~/.local/state was not loaded")
assert(#rules == 1, "expected 1 workspace rule from ~/.local/state, got " .. #rules)
assert(rules[1].workspace == "3" and rules[1].layout == "scrolling")
LUA
pass "toggles and workspace layouts load from ~/.local/state when XDG_STATE_HOME is set elsewhere"
