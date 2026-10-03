#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/home"

cat >"$mock_bin/omarchy-done" <<'SH'
#!/bin/bash
[[ $1 == "check" && $2 == "first-run-user" ]]
SH
cat >"$mock_bin/omarchy-provision-user" <<'SH'
#!/bin/bash
touch "$OMARCHY_TEST_FINALIZE_CALLED"
SH
chmod +x "$mock_bin/omarchy-done" "$mock_bin/omarchy-provision-user"

finalize_called="$test_tmp/finalize-called"
HOME="$test_tmp/home" PATH="$mock_bin:$PATH" OMARCHY_TEST_FINALIZE_CALLED="$finalize_called" \
  bash "$ROOT/bin/omarchy-provision-first-run" >"$test_tmp/output"

[[ ! -e $finalize_called ]] || fail "completed first-run exits before any setup step"
grep -F 'First-run already complete' "$test_tmp/output" >/dev/null || fail "completed first-run reports its lifecycle gate"

if grep -F 'user-migration-notify-watch-enabled' "$ROOT/bin/omarchy-provision-first-run" >/dev/null; then
  fail "first-run does not track the migration watcher separately"
fi
if grep -F 'skip-first-run-update-notification' "$ROOT/install/user/first-run/wifi.sh" >/dev/null; then
  fail "first-run does not track update notifications separately"
fi

pass "first-run uses one lifecycle completion marker"

cat >"$mock_bin/gsettings" <<'SH'
#!/bin/bash
echo "$*" >>"$OMARCHY_TEST_GSETTINGS_LOG"
SH
chmod +x "$mock_bin/gsettings"

run_first_run_gnome_theme() {
  local theme="$1"
  local theme_home="$test_tmp/gnome-$theme"

  mkdir -p "$theme_home/.local/state/omarchy/current"
  ln -snf "$ROOT/themes/$theme" "$theme_home/.local/state/omarchy/current/theme"

  HOME="$theme_home" PATH="$mock_bin:$ROOT/bin:$PATH" OMARCHY_PATH="$ROOT" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$test_tmp/bus" OMARCHY_TEST_GSETTINGS_LOG="$theme_home/gsettings.log" \
    bash "$ROOT/install/user/first-run/gnome-theme.sh"
  cat "$theme_home/gsettings.log"
}

gsettings_calls=$(run_first_run_gnome_theme tokyo-night)
grep -Fx 'set org.gnome.desktop.interface icon-theme Yaru-magenta' <<<"$gsettings_calls" >/dev/null ||
  fail "first-run GNOME theme applies the current theme's icons" "$gsettings_calls"
grep -Fx 'set org.gnome.desktop.interface color-scheme prefer-dark' <<<"$gsettings_calls" >/dev/null ||
  fail "first-run GNOME theme keeps dark themes dark" "$gsettings_calls"

gsettings_calls=$(run_first_run_gnome_theme catppuccin-latte)
grep -Fx 'set org.gnome.desktop.interface color-scheme prefer-light' <<<"$gsettings_calls" >/dev/null ||
  fail "first-run GNOME theme applies light mode for light themes" "$gsettings_calls"
grep -Fx 'set org.gnome.desktop.interface gtk-theme Adwaita' <<<"$gsettings_calls" >/dev/null ||
  fail "first-run GNOME theme uses the light GTK theme for light themes" "$gsettings_calls"

pass "first-run GNOME theme follows the current theme"
