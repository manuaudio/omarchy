#!/bin/bash

source "$(dirname -- "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$OMARCHY_TEST_LOG"
exit "${OMARCHY_TEST_PKG_ADD_STATUS:-0}"
SH

for command in omarchy-theme-set-vscode setsid; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$OMARCHY_TEST_LOG"
SH
done

chmod +x "$mock_bin"/*

export OMARCHY_TEST_LOG="$test_tmp/log"

run_installer() {
  local home="$1"

  HOME="$home" PATH="$mock_bin:$PATH" bash "$ROOT/bin/omarchy-install-editor-vscode" >/dev/null 2>&1
}

# VS Code reads both files as JSONC; strip comments and trailing commas to check them
jsonc_value() {
  local file="$1"
  local key="$2"

  sed -E 's|^[[:space:]]*//.*||' "$file" | tr '\n' ' ' | sed -E 's/,[[:space:]]*}/}/g' | jq -r --arg key "$key" '.[$key]'
}

assert_key_once() {
  local file="$1"
  local key="$2"
  local description="$3"
  local count

  count=$(grep -c "\"$key\"" "$file")
  (( count == 1 )) || fail "$description" "expected one \"$key\" in $file, found $count:
$(cat "$file")"
}

# Existing settings and argv entries survive the install
existing_home="$test_tmp/existing"
mkdir -p "$existing_home/.config/Code/User" "$existing_home/.vscode"
cat >"$existing_home/.config/Code/User/settings.json" <<'JSON'
{
  "editor.fontSize": 15
}
JSON
cat >"$existing_home/.vscode/argv.json" <<'JSON'
// User argv
{
  "disable-hardware-acceleration": true
}
JSON

run_installer "$existing_home" || fail "installer succeeds with existing config"
settings="$existing_home/.config/Code/User/settings.json"
argv="$existing_home/.vscode/argv.json"

[[ $(jsonc_value "$settings" editor.fontSize) == "15" ]] ||
  fail "installer keeps existing VS Code settings" "$(cat "$settings")"
[[ $(jsonc_value "$settings" update.mode) == "none" ]] ||
  fail "installer adds update.mode to existing settings" "$(cat "$settings")"
[[ $(jsonc_value "$argv" disable-hardware-acceleration) == "true" ]] ||
  fail "installer keeps existing argv.json entries" "$(cat "$argv")"
[[ $(jsonc_value "$argv" password-store) == "gnome-libsecret" ]] ||
  fail "installer adds password-store to existing argv.json" "$(cat "$argv")"
grep -Fqx "// User argv" "$argv" || fail "installer keeps argv.json comments" "$(cat "$argv")"
pass "installer keeps existing VS Code settings and argv entries"

# A second run adds nothing
cp "$settings" "$test_tmp/settings.before"
cp "$argv" "$test_tmp/argv.before"
run_installer "$existing_home" || fail "installer succeeds on a second run"
cmp -s "$settings" "$test_tmp/settings.before" || fail "second run leaves settings.json unchanged" "$(cat "$settings")"
cmp -s "$argv" "$test_tmp/argv.before" || fail "second run leaves argv.json unchanged" "$(cat "$argv")"
assert_key_once "$settings" update.mode "second run does not duplicate update.mode"
assert_key_once "$argv" password-store "second run does not duplicate password-store"
pass "installer is idempotent"

# A fresh home gets both files seeded
fresh_home="$test_tmp/fresh"
mkdir -p "$fresh_home"
run_installer "$fresh_home" || fail "installer succeeds in a fresh home"
[[ $(jsonc_value "$fresh_home/.config/Code/User/settings.json" update.mode) == "none" ]] ||
  fail "installer seeds settings.json with update.mode"
[[ $(jsonc_value "$fresh_home/.vscode/argv.json" password-store) == "gnome-libsecret" ]] ||
  fail "installer seeds argv.json with password-store"
pass "installer seeds VS Code config in a fresh home"

# A failed package install leaves existing config untouched
failed_home="$test_tmp/failed"
mkdir -p "$failed_home/.config/Code/User" "$failed_home/.vscode"
printf '{\n  "editor.fontSize": 15\n}\n' >"$failed_home/.config/Code/User/settings.json"
printf '{\n  "disable-hardware-acceleration": true\n}\n' >"$failed_home/.vscode/argv.json"
cp "$failed_home/.config/Code/User/settings.json" "$test_tmp/failed-settings.before"
cp "$failed_home/.vscode/argv.json" "$test_tmp/failed-argv.before"
: >"$OMARCHY_TEST_LOG"

if OMARCHY_TEST_PKG_ADD_STATUS=1 run_installer "$failed_home"; then
  fail "installer exits non-zero when the package install fails"
fi
cmp -s "$failed_home/.config/Code/User/settings.json" "$test_tmp/failed-settings.before" ||
  fail "failed install leaves settings.json untouched"
cmp -s "$failed_home/.vscode/argv.json" "$test_tmp/failed-argv.before" ||
  fail "failed install leaves argv.json untouched"
if grep -q "^omarchy-theme-set-vscode\|^setsid" "$OMARCHY_TEST_LOG"; then
  fail "failed install does not theme or launch VS Code" "$(cat "$OMARCHY_TEST_LOG")"
fi
pass "installer stops when the package install fails"
