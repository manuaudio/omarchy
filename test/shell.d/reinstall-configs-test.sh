#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

skel="$test_tmp/skel"
test_home="$test_tmp/home"
stub_bin="$test_tmp/bin"
markers=.local/state/omarchy/migrations
mkdir -p "$skel/$markers" "$skel/.config/hypr" "$test_home/$markers" "$test_home/.config/hypr" "$stub_bin"

for command in omarchy-refresh-limine omarchy-refresh-plymouth omarchy-nvim-refresh; do
  printf '#!/bin/bash\necho %s >>"$TEST_CALLS"\n' "$command" >"$stub_bin/$command"
  chmod +x "$stub_bin/$command"
done

# The omarchy package seeds /etc/skel with a marker for every shipped migration.
mapfile -t migrations < <(cd "$ROOT/migrations" && printf '%s\n' *.sh)
for migration in "${migrations[@]}"; do
  touch "$skel/$markers/$migration"
done
echo "shipped" >"$skel/.config/hypr/bindings.lua"

# This user is behind: every migration has run except the newest two.
for migration in "${migrations[@]:0:${#migrations[@]}-2}"; do
  touch "$test_home/$markers/$migration"
done
echo "edited" >"$test_home/.config/hypr/bindings.lua"

# The command refuses to run as root, so a root test run maps itself to an
# ordinary uid in a user namespace.
runner=()
if (( EUID == 0 )); then
  if unshare --user --map-user=1000 --map-group=1000 true 2>/dev/null; then
    runner=(unshare --user --map-user=1000 --map-group=1000)
  else
    skip "omarchy-reinstall-configs needs a non-root user and unshare is unavailable"
    exit 0
  fi
fi

run_as_user() {
  "${runner[@]}" env HOME="$test_home" OMARCHY_PATH="$ROOT" OMARCHY_SKEL_DIR="$skel" \
    PATH="$stub_bin:$ROOT/bin:$PATH" TEST_CALLS="$test_tmp/calls" "$@"
}

run_as_user bash "$ROOT/bin/omarchy-reinstall-configs" >/dev/null ||
  fail "omarchy-reinstall-configs finishes"

[[ $(<"$test_home/.config/hypr/bindings.lua") == "shipped" ]] ||
  fail "omarchy-reinstall-configs resets configs to the shipped defaults"
[[ $(<"$test_tmp/calls") == $'omarchy-refresh-limine\nomarchy-refresh-plymouth\nomarchy-nvim-refresh' ]] ||
  fail "omarchy-reinstall-configs refreshes limine, plymouth and nvim" "$(<"$test_tmp/calls")"
pass "omarchy-reinstall-configs resets configs to the shipped defaults"

pending=$(run_as_user bash "$ROOT/bin/omarchy-migrate" --pending || true)
[[ $pending == "${migrations[-2]}"$'\n'"${migrations[-1]}" ]] ||
  fail "omarchy-reinstall-configs keeps the user's pending migrations pending" "pending after reset: ${pending:-none}"
pass "omarchy-reinstall-configs keeps the user's pending migrations pending"
