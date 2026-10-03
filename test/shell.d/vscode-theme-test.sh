#!/bin/bash

source "$(dirname "$0")/base-test.sh"

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

FAKE_BIN="$TEST_HOME/bin"
CURRENT_THEME="$TEST_HOME/.local/state/omarchy/current/theme"
mkdir -p "$FAKE_BIN" "$CURRENT_THEME"

cat >"$FAKE_BIN/omarchy-cmd-present" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >>"$EDITOR_PROBE_LOG"
exit 1
EOF

cat >"$FAKE_BIN/omarchy-toggle-enabled" <<'EOF'
#!/bin/bash
exit 1
EOF

cat >"$FAKE_BIN/cursor" <<'EOF'
#!/bin/bash
touch "$CURSOR_SHIM_CALLED"
exit 1
EOF

chmod +x "$FAKE_BIN"/*
printf '{"name":"Hackerman","extension":"akamud.vscode-theme-onedark"}\n' >"$CURRENT_THEME/vscode.json"

EDITOR_PROBE_LOG="$TEST_HOME/editor-probes.log" \
  CURSOR_SHIM_CALLED="$TEST_HOME/cursor-shim-called" \
  PATH="$FAKE_BIN:$ROOT/bin:$PATH" \
  HOME="$TEST_HOME" \
  "$ROOT/bin/omarchy-theme-set-vscode"

grep -Fxq '/usr/bin/cursor' "$TEST_HOME/editor-probes.log" || fail "VS Code theme sync probes the packaged Cursor executable"
[[ ! -e $TEST_HOME/cursor-shim-called ]] || fail "VS Code theme sync ignores a PATH-provided Cursor Agent shim"
[[ ! -e $TEST_HOME/.config/Cursor/User/settings.json ]] || fail "VS Code theme sync skips Cursor when the packaged executable is unavailable"
pass "VS Code theme sync selects the packaged Cursor executable"

# settings.json is JSONC: a commented-out colorTheme must not stand in for the
# live key, and an empty file must still receive one.
JSONC_HOME="$TEST_HOME/jsonc"
JSONC_BIN="$JSONC_HOME/bin"
JSONC_SETTINGS="$JSONC_HOME/.config/Code/User/settings.json"
mkdir -p "$JSONC_BIN" "$JSONC_HOME/.local/state/omarchy/current/theme" "$(dirname "$JSONC_SETTINGS")"

cat >"$JSONC_BIN/omarchy-cmd-present" <<'EOF'
#!/bin/bash
[[ $1 == "code" ]]
EOF

cp "$FAKE_BIN/omarchy-toggle-enabled" "$JSONC_BIN/"
chmod +x "$JSONC_BIN"/*
printf '{"name":"Omarchy"}\n' >"$JSONC_HOME/.local/state/omarchy/current/theme/vscode.json"

run_jsonc_sync() {
  PATH="$JSONC_BIN:$ROOT/bin:$PATH" HOME="$JSONC_HOME" "$ROOT/bin/omarchy-theme-set-vscode"
}

cat >"$JSONC_SETTINGS" <<'EOF'
{
  // "workbench.colorTheme": "Dracula",
  "editor.fontSize": 14
}
EOF

run_jsonc_sync

grep -Eq '^[[:space:]]*(\{[[:space:]]*)?"workbench\.colorTheme": "Omarchy",' "$JSONC_SETTINGS" || fail "VS Code theme sync adds a live colorTheme key beside a commented one"
grep -Fxq '  // "workbench.colorTheme": "Dracula",' "$JSONC_SETTINGS" || fail "VS Code theme sync leaves a commented colorTheme line untouched"
pass "VS Code theme sync ignores a commented-out colorTheme key"

: >"$JSONC_SETTINGS"

run_jsonc_sync

grep -Fq '"workbench.colorTheme": "Omarchy"' "$JSONC_SETTINGS" || fail "VS Code theme sync writes colorTheme into an empty settings file"
require_command node
node -e '
  const text = require("fs").readFileSync(process.argv[1], "utf8")
  JSON.parse(text.replace(/,(\s*[}\]])/g, "$1"))
' "$JSONC_SETTINGS" || fail "VS Code theme sync leaves an empty settings file as valid JSONC"
pass "VS Code theme sync seeds an empty settings file"
