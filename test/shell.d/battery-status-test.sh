#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
mkdir -p "$tmp_dir/power/BAT0"
printf '900000\n' >"$tmp_dir/power/BAT0/current_now"
printf '12000000\n' >"$tmp_dir/power/BAT0/voltage_now"
cat >"$tmp_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  exit 0
fi

if [[ $1 == "-i" ]]; then
  cat <<'INFO'
  native-path:          BAT0
  state:                discharging
  energy:               28.3 Wh
  energy-full:          56.7 Wh
  energy-rate:          7.3 W
INFO
  printf '  time to empty:        %s\n' "${UPOWER_TIME:-2.5 hours}"
  cat <<'INFO'
  percentage:           51%
INFO
  exit 0
fi

exit 1
STUB
chmod +x "$tmp_dir/bin/upower"

shell_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t51%' <<<"$shell_output" >/dev/null || fail "battery status reports percentage"
grep -Fx $'state\tdischarging' <<<"$shell_output" >/dev/null || fail "battery status reports state"
grep -Fx $'rate\t10.8W' <<<"$shell_output" >/dev/null || fail "battery status reports live sysfs power rate"
grep -Fx $'size\t56Wh' <<<"$shell_output" >/dev/null || fail "battery status reports full capacity"
grep -Fx $'time\t2h 30m' <<<"$shell_output" >/dev/null || fail "battery status reports remaining time"

battery_time() {
  OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" UPOWER_TIME="$1" "$ROOT/bin/omarchy-battery-status" --shell | awk -F '\t' '$1 == "time" { print $2 }'
}

remaining=$(battery_time "42 seconds")
[[ $remaining == "0m" ]] || fail "battery status reports sub-minute remaining time as minutes" "$remaining"
remaining=$(battery_time "30.0 minutes")
[[ $remaining == "30m" ]] || fail "battery status reports remaining minutes" "$remaining"
remaining=$(battery_time "2.6 days")
[[ $remaining == "62h 24m" ]] || fail "battery status reports remaining days as hours" "$remaining"
remaining=$(battery_time "2.8 days")
[[ $remaining == "67h 12m" ]] || fail "battery status rounds remaining days to whole minutes" "$remaining"
remaining=$(battery_time "2.3 hours")
[[ $remaining == "2h 18m" ]] || fail "battery status rounds remaining hours to whole minutes" "$remaining"

if matches=$(rg -n 'omarchy-battery-(capacity|remaining|remaining-time)' "$ROOT/bin" "$ROOT/test" "$ROOT/shell" "$ROOT/docs"); then
  fail "battery status owns capacity and remaining calculations" "$matches"
fi

pass "battery status owns capacity and remaining calculations"
