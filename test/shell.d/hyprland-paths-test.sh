#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

run_paths() {
  lua - <<'LUA'
package.path = os.getenv("OMARCHY_PATH") .. "/?.lua;" .. package.path
local paths = require("default.hypr.paths")
assert(paths.config_home == os.getenv("EXPECTED_CONFIG"), "config_home: " .. paths.config_home)
LUA
}

HOME="/home/test-user" OMARCHY_PATH="$ROOT" \
  XDG_CONFIG_HOME= \
  EXPECTED_CONFIG="/home/test-user/.config" \
  run_paths
pass "empty XDG_CONFIG_HOME falls back to its default"

HOME="/home/test-user" OMARCHY_PATH="$ROOT" \
  XDG_CONFIG_HOME="/custom/config" \
  EXPECTED_CONFIG="/custom/config" \
  run_paths
pass "set XDG_CONFIG_HOME is honored"
