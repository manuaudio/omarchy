#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

# pw-metadata keeps clock.force-quantum in a file; reads print it the way
# PipeWire does.
cat >"$tmp/bin/pw-metadata" <<SH
#!/bin/bash
state="$tmp/quantum"
if (( \$# == 5 )); then
  echo "\$5" >"\$state"
elif [[ -f \$state ]]; then
  echo "Found \"settings\" metadata 30"
  echo "update: id:0 key:'clock.force-quantum' value:'\$(cat "\$state")' type:''"
fi
SH
printf '#!/bin/bash\necho "$*" >>"%s/notifications"\n' "$tmp" >"$tmp/bin/omarchy-notification-send"
printf '#!/bin/bash\n[[ ${RTKIT_MISSING:-0} == 1 ]]\n' >"$tmp/bin/omarchy-pkg-missing"
chmod +x "$tmp/bin/"*

toggle() {
  PATH="$tmp/bin:$PATH" "$ROOT/bin/omarchy-toggle-low-latency-audio" "$@"
}

rm -f "$tmp/quantum"
! toggle --status || fail "low-latency audio starts off when PipeWire has no forced quantum"
pass "low-latency audio starts off when PipeWire has no forced quantum"

toggle
[[ $(cat "$tmp/quantum") == 256 ]] || fail "toggling on forces a 256-sample quantum" "$(cat "$tmp/quantum")"
toggle --status || fail "status reports low-latency audio on"
pass "toggling on forces a 256-sample quantum and status reports it"

toggle
[[ $(cat "$tmp/quantum") == 0 ]] || fail "toggling off clears the forced quantum"
! toggle --status || fail "status reports low-latency audio off"
pass "toggling off clears the forced quantum"

toggle on && toggle on
[[ $(cat "$tmp/quantum") == 256 ]] || fail "on is idempotent"
toggle off
[[ $(cat "$tmp/quantum") == 0 ]] || fail "off clears the forced quantum"
pass "on and off set the state explicitly"

: >"$tmp/notifications"
RTKIT_MISSING=1 toggle on
grep -q "Install rtkit" "$tmp/notifications" || fail "turning on without rtkit explains the missing realtime priority" "$(cat "$tmp/notifications")"
: >"$tmp/notifications"
RTKIT_MISSING=0 toggle on
! grep -q "rtkit" "$tmp/notifications" || fail "turning on with rtkit shows no rtkit hint" "$(cat "$tmp/notifications")"
pass "the rtkit hint appears only when rtkit is missing"

if toggle sideways 2>/dev/null; then
  fail "an unknown argument is rejected"
fi
pass "an unknown argument is rejected"

grep -qF '"checked":"omarchy-toggle-low-latency-audio --status","action":"omarchy-toggle-low-latency-audio"' "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "the toggle menu offers low-latency audio with its state checked"
pass "the toggle menu offers low-latency audio with its state checked"
