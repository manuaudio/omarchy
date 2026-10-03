#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

# Real v4l2-ctl --list-devices output: each header ends with a ":" delimiter
cat >"$stub_bin/v4l2-ctl" <<'SH'
#!/bin/bash

case "$1" in
--list-devices)
  printf '%s\n' "Integrated Camera: Integrated C (usb-0000:00:14.0-8):"
  printf '\t%s\n' "/dev/video0" "/dev/video1" "/dev/media0"
  printf '\n%s\n' "ipu6 (PCI:0000:00:05.0):"
  printf '\t%s\n' "/dev/video2" "/dev/media1"
  ;;
--device)
  case "$2" in
  /dev/video0) device_capability="Video Capture" ;;
  *) device_capability="Metadata Capture" ;;
  esac

  printf '%s\n' \
    "Driver Info:" \
    $'\tCapabilities     : 0x84a00001' \
    $'\t\tVideo Capture' \
    $'\tDevice Caps      : 0x04200001' \
    $'\t\t'"$device_capability"
  ;;
esac
SH

chmod +x "$stub_bin/v4l2-ctl"

export PATH="$stub_bin:$ROOT/bin:$PATH"

actual=$(omarchy-capture-webcam-list)
expected="/dev/video0  Integrated Camera: Integrated C (usb-0000:00:14.0-8)"

[[ $actual == "$expected" ]] ||
  fail "webcam list drops the trailing colon from v4l2-ctl device headers" \
    "expected: $expected"$'\n'"actual:   $actual"
pass "webcam list drops the trailing colon from v4l2-ctl device headers"
