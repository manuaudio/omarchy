#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
stub_bin="$test_tmp/bin"
current_state="$test_home/.local/state/omarchy/current"
theme_name="test-theme"
mkdir -p "$stub_bin" "$current_state/theme/backgrounds" "$test_home/.config/omarchy/backgrounds" "$test_home/Pictures/walls"
printf '%s\n' "$theme_name" >"$current_state/theme.name"

# bg-set hands the background to the running shell; the test has none.
printf '#!/bin/bash\n' >"$stub_bin/omarchy-shell"
printf '#!/bin/bash\n' >"$stub_bin/omarchy-notification-send"
chmod +x "$stub_bin/omarchy-shell" "$stub_bin/omarchy-notification-send"

bg_next() {
  HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$stub_bin:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-theme-bg-next"
}

current_background_name() {
  basename "$(readlink "$current_state/background")"
}

# The user's backgrounds folder for the theme is a symlink to another folder,
# and one background in it is itself a symlink to a file elsewhere.
printf 'one\n' >"$test_home/Pictures/walls/1.png"
printf 'two\n' >"$test_tmp/2-target.png"
ln -s "$test_tmp/2-target.png" "$test_home/Pictures/walls/2.png"
ln -s "$test_home/Pictures/walls" "$test_home/.config/omarchy/backgrounds/$theme_name"

bg_next
[[ $(current_background_name) == "1.png" ]] || fail "bg next starts at the first symlinked background"
pass "bg next starts at the first symlinked background"

bg_next
[[ $(current_background_name) == "2-target.png" ]] || fail "bg next advances through a symlinked backgrounds folder"
pass "bg next advances through a symlinked backgrounds folder"

bg_next
[[ $(current_background_name) == "1.png" ]] || fail "bg next wraps past a symlinked background file"
pass "bg next wraps past a symlinked background file"

# Reapplying the active theme cycles from the background bg next left behind,
# which bg set stored as its resolved path.
source <(awk '
  /^(theme_background_state_file|choose_theme_background)\(\) \{/ { copying=1 }
  copying { print }
  copying && /^}$/ { copying=0 }
' "$ROOT/bin/omarchy-theme-set")

HOME="$test_home"
CURRENT_THEME_PATH="$current_state/theme"
CURRENT_BACKGROUND_LINK="$current_state/background"
THEME_BACKGROUND_STATE_PATH="$test_home/.local/state/omarchy/theme-backgrounds"
THEME_NAME="$theme_name"
PREVIOUS_THEME_NAME="$theme_name"
choose_theme_background
[[ $CHOSEN_THEME_BACKGROUND == "$test_home/.config/omarchy/backgrounds/$theme_name/2.png" ]] || fail "reapplying the theme cycles from a resolved background path" "chose $CHOSEN_THEME_BACKGROUND"
pass "reapplying the theme cycles from a resolved background path"
