#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

conf="pipewire/pipewire.conf.d/10-sample-rates.conf"
rates="[ 44100 48000 88200 96000 ]"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# PipeWire's own parser merges the drop-in into the rates it runs with.
if command -v pw-config >/dev/null; then
  mkdir -p "$tmp/xdg/pipewire/pipewire.conf.d"
  cp "$ROOT/config/$conf" "$tmp/xdg/$conf"
  merged=$(XDG_CONFIG_HOME="$tmp/xdg" pw-config --name pipewire.conf merge context.properties 2>/dev/null | tr -s ' \n' ' ')
  [[ $merged == *"\"default.clock.allowed-rates\": $rates"* ]] ||
    fail "PipeWire reads the shipped sample rates" "$merged"
  pass "PipeWire reads the shipped sample rates"
else
  skip "pw-config not installed; skipping the PipeWire parse check"
fi

migration=$(grep -rl "Let PipeWire follow the source's sample rate" "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "the sample-rate migration exists"

mkdir -p "$tmp/bin" "$tmp/home"
printf '#!/bin/bash\necho "$*" >>"%s/pw-metadata.log"\n' "$tmp" >"$tmp/bin/pw-metadata"
chmod +x "$tmp/bin/pw-metadata"

run_migration() {
  : >"$tmp/pw-metadata.log"
  HOME="$tmp/home" OMARCHY_PATH="$ROOT" PATH="$tmp/bin:$ROOT/bin:$PATH" bash -euo pipefail "$migration" >/dev/null
}

run_migration
cmp -s "$ROOT/config/$conf" "$tmp/home/.config/$conf" || fail "the migration installs the sample-rate config"
[[ $(cat "$tmp/pw-metadata.log") == "-n settings 0 clock.allowed-rates $rates" ]] ||
  fail "the migration applies the rates to the running graph" "$(cat "$tmp/pw-metadata.log")"
pass "the migration installs the sample-rate config and applies it without a restart"

# A user who already has the file keeps their own rates.
echo "context.properties = { default.clock.allowed-rates = [ 48000 ] }" >"$tmp/home/.config/$conf"
run_migration
grep -q "\[ 48000 \]" "$tmp/home/.config/$conf" || fail "the migration leaves a user's own sample-rate config alone"
[[ ! -s $tmp/pw-metadata.log ]] || fail "the migration leaves the running rates alone when the user has their own config"
pass "the migration leaves a user's own sample-rate config alone"
