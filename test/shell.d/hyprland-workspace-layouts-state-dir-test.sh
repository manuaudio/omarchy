#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home_dir="$tmpdir/home"
xdg_decoy="$tmpdir/xdg-state"
layouts_dir="$home_dir/.local/state/omarchy/workspace-layouts"
mkdir -p "$layouts_dir" "$xdg_decoy"

# omarchy-hyprland-workspace-layout-toggle always writes under ~/.local/state,
# and bootstrap.lua resolves omarchy.workspace-layouts.* there too, so the Lua
# reader must load from there even when XDG_STATE_HOME points somewhere else.
printf 'hl.workspace_rule({ workspace = "3", layout = "scrolling" })\n' >"$layouts_dir/3.lua"

HOME="$home_dir" XDG_STATE_HOME="$xdg_decoy" OMARCHY_PATH="$ROOT" lua - <<'LUA'
local rules = {}

hl = {
  workspace_rule = function(rule)
    table.insert(rules, rule)
  end,
}

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("default.hypr.workspace-layouts")

assert(#rules == 1, "expected 1 workspace rule from ~/.local/state, got " .. #rules)
assert(rules[1].workspace == "3" and rules[1].layout == "scrolling")
LUA
pass "workspace layouts load from ~/.local/state when XDG_STATE_HOME is set elsewhere"
