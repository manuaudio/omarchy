#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"

cat >"$tmp_dir/bin/omarchy-pkg-drop" <<'SCRIPT'
#!/bin/bash
printf 'drop:%s\n' "$*" >>"$TEST_LOG"
SCRIPT

# Reports the packages listed in TEST_PRESENT as installed.
cat >"$tmp_dir/bin/omarchy-pkg-present" <<'SCRIPT'
#!/bin/bash
for pkg in "$@"; do
  [[ " ${TEST_PRESENT:-} " == *" $pkg "* ]] || exit 1
done
SCRIPT

# Logs every prompt and answers "no" so no optional removal runs.
cat >"$tmp_dir/bin/gum" <<'SCRIPT'
#!/bin/bash
printf 'gum:%s\n' "$*" >>"$TEST_LOG"
exit 1
SCRIPT

# The Battle.net removal kills processes by prefix path and refreshes the
# desktop database; neither may touch the developer's session.
for stub in pkill sleep update-desktop-database; do
  printf '#!/bin/bash\nexit 0\n' >"$tmp_dir/bin/$stub"
done

chmod +x "$tmp_dir/bin/"*

export TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir/bin:$PATH"

fresh_home() {
  rm -rf "$tmp_dir/home" "$TEST_LOG"
  touch "$TEST_LOG"
  mkdir -p "$tmp_dir/home/.local/share/umu"
  export HOME="$tmp_dir/home"
}

add_battlenet_prefix() {
  local launcher_dir="$HOME/Games/battlenet/drive_c/Program Files (x86)/Battle.net"
  mkdir -p "$launcher_dir"
  touch "$launcher_dir/Battle.net Launcher.exe"
}

# Battle.net runs through umu-run, so removing Lutris must leave umu alone
# while a Battle.net prefix exists.
fresh_home
add_battlenet_prefix
"$ROOT/bin/omarchy-remove-gaming-lutris" >/dev/null

grep -q '^drop:.*lutris' "$TEST_LOG" || fail "Lutris removal drops lutris" "$(cat "$TEST_LOG")"
! grep -q 'umu-launcher' "$TEST_LOG" || fail "Lutris removal keeps umu-launcher while Battle.net is installed" "$(cat "$TEST_LOG")"
[[ -d $HOME/.local/share/umu ]] || fail "Lutris removal keeps umu data while Battle.net is installed"
pass "Lutris removal keeps umu while Battle.net is installed"

fresh_home
"$ROOT/bin/omarchy-remove-gaming-lutris" >/dev/null

grep -q '^drop:.*umu-launcher' "$TEST_LOG" || fail "Lutris removal drops umu-launcher without Battle.net" "$(cat "$TEST_LOG")"
[[ ! -e $HOME/.local/share/umu ]] || fail "Lutris removal deletes umu data without Battle.net"
pass "Lutris removal drops umu without Battle.net"

# Lutris uses umu as a runner, so removing Battle.net must not offer to drop it
# while Lutris is installed.
fresh_home
add_battlenet_prefix
TEST_PRESENT="umu-launcher lutris" "$ROOT/bin/omarchy-remove-gaming-battlenet" >/dev/null

! grep -q 'umu-launcher' "$TEST_LOG" || fail "Battle.net removal does not offer umu-launcher while Lutris is installed" "$(cat "$TEST_LOG")"
pass "Battle.net removal does not offer umu-launcher while Lutris is installed"

fresh_home
add_battlenet_prefix
TEST_PRESENT="umu-launcher" "$ROOT/bin/omarchy-remove-gaming-battlenet" >/dev/null

grep -q '^gum:.*umu-launcher' "$TEST_LOG" || fail "Battle.net removal offers umu-launcher without Lutris" "$(cat "$TEST_LOG")"
pass "Battle.net removal offers umu-launcher without Lutris"
