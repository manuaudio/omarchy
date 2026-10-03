#!/bin/bash

set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

# 1789095456 was reused after a kernel migration of the same name had already
# been marked complete, so 1791058181 re-runs the Mise PATH repair wherever its
# leftover state shows it never ran, and nowhere else.
migration="$ROOT/migrations/1791058181.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"
cat >"$test_dir/bin/mise" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$MISE_TEST_LOG"
SH
chmod +x "$test_dir/bin/mise"

run_migration() {
  local test_home="$1"

  env -i \
    HOME="$test_home" \
    XDG_CACHE_HOME="$test_home/.cache" \
    XDG_CONFIG_HOME="$test_home/.config" \
    XDG_DATA_HOME="$test_home/.local/share" \
    XDG_STATE_HOME="$test_home/.local/state" \
    MISE_TEST_LOG="$test_home/mise.log" \
    OMARCHY_PATH="$ROOT" \
    PATH="$test_dir/bin:/usr/bin" \
    bash -euo pipefail "$migration"
}

stock_home="$test_dir/stock-home"
stock_config="$stock_home/Work/.mise.toml"
mkdir -p "$stock_home/Work/tries"
printf '[env]\n_.path = "{{ cwd }}/bin"\n' >"$stock_config"
[[ $(sha256sum "$stock_config" | cut -d ' ' -f 1) == "bd04f191d63bbde86920f44f76f0989fad980afc84e268e8474c201ec7149245" ]] || fail "test writes the config Omarchy 4.0.3 shipped"
run_migration "$stock_home" >/dev/null || fail "migration succeeds over the stock config"
[[ ! -e $stock_config ]] || fail "migration removes the stock Work Mise config"
grep -qxF "trust --untrust $stock_config" "$stock_home/mise.log" || fail "migration revokes trust for the stock config" "$(cat "$stock_home/mise.log")"
pass "stock Work config left by the skipped repair is removed and untrusted"

custom_home="$test_dir/custom-home"
custom_config="$custom_home/Work/.mise.toml"
mkdir -p "$custom_home/Work"
printf '[env]\nKEEP = "yes"\n_.path = "{{ cwd }}/bin"\n\n[tools]\nruby = "latest"\n' >"$custom_config"
printf '[env]\nKEEP = "yes"\n\n[tools]\nruby = "latest"\n' >"$test_dir/custom-expected"
run_migration "$custom_home" >/dev/null || fail "migration succeeds over a custom config with the unsafe path"
cmp -s "$test_dir/custom-expected" "$custom_config" || fail "migration removes only the unsafe path line" "$(cat "$custom_config")"
grep -qxF "trust --untrust $custom_config" "$custom_home/mise.log" || fail "migration revokes trust for the repaired config" "$(cat "$custom_home/mise.log")"
pass "unsafe project bin path is removed from a custom config"

clean_home="$test_dir/clean-home"
clean_config="$clean_home/Work/.mise.toml"
mkdir -p "$clean_home/Work"
printf '[env]\nKEEP = "yes"\n\n[other]\n_.path = "{{ cwd }}/bin"\n' >"$clean_config"
cp "$clean_config" "$test_dir/clean-original"
output=$(run_migration "$clean_home") || fail "migration succeeds over a clean config"
cmp -s "$test_dir/clean-original" "$clean_config" || fail "clean custom config is untouched"
[[ ! -e $clean_home/mise.log ]] || fail "trust is not revoked for a config already repaired" "$(cat "$clean_home/mise.log")"
[[ $output != *"revoked"* ]] || fail "nothing is reported for a config already repaired" "$output"
pass "a config the first repair already cleaned keeps its trust"

absent_home="$test_dir/absent-home"
mkdir -p "$absent_home"
run_migration "$absent_home" >/dev/null || fail "migration succeeds without a Work directory"
[[ ! -e $absent_home/Work ]] || fail "migration does not create a Work directory"
[[ ! -e $absent_home/mise.log ]] || fail "mise is not called without a Work directory"

empty_home="$test_dir/empty-home"
mkdir -p "$empty_home/Work"
run_migration "$empty_home" >/dev/null || fail "migration succeeds without a Work Mise config"
[[ ! -e $empty_home/Work/.mise.toml ]] || fail "migration does not create a Work Mise config"
[[ ! -e $empty_home/mise.log ]] || fail "mise is not called without a Work Mise config"
pass "migration is a no-op without a Work Mise config"
