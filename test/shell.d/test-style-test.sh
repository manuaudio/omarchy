#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# lua runs a script piped to stdin without a `-` argument, but exits 0 when it errors,
# so every assert in a bare `lua <<'LUA'` block passes no matter what. `lua -` exits 1.
bare_lua_heredocs=$(rg -n -P '(^|[\s;|&(])lua(5\.?[0-9])?\s+<<' "$ROOT/test" || true)
[[ -z $bare_lua_heredocs ]] || fail "tests feed Lua heredocs to lua -, so a failing script fails the test" "$bare_lua_heredocs"
pass "tests feed Lua heredocs to lua -, so a failing script fails the test"
