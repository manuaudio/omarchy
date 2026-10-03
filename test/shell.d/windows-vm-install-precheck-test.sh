#!/bin/bash
# The install flow offers a 32G disk when 64G does not fit, so its early
# prerequisite check must not demand room for 64G before the picker runs.

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export OMARCHY_WINDOWS_DIR="$TMPDIR/win"
export HOME="$TMPDIR/home"
mkdir -p "$HOME"

set -- help
source "$ROOT/bin/omarchy-windows-vm" >/dev/null 2>&1
set +eu

# Point the KVM probe at a stand-in file so the test never depends on, or
# touches, the real /dev/kvm.
FAKE_KVM="$TMPDIR/kvm"
touch "$FAKE_KVM"
eval "$(declare -f check_prerequisites | sed "s|/dev/kvm|$FAKE_KVM|g")"
declare -f check_prerequisites | grep -qF "$FAKE_KVM" || fail "KVM probe can be redirected"

PICKER_LOG="$TMPDIR/picker"
OUT="$TMPDIR/out"

prepare_user_mount_sources() { :; }
available_storage_gb() { echo "$FAKE_AVAILABLE_GB"; }
omarchy-pkg-add() { :; }

# Answer the RAM and core prompts, then record the disk picker's options and
# default and cancel there, before anything privileged would run.
gum() {
  local selected="" header="" arg
  for arg in "$@"; do
    case $arg in
    --selected=*) selected=${arg#--selected=} ;;
    --header=*) header=${arg#--header=} ;;
    esac
  done

  case $1:$header in
  choose:*RAM*) echo 4G ;;
  input:*CPU*) echo 2 ;;
  choose:*disk*)
    {
      echo "selected=$selected"
      echo "options=$(tr '\n' ' ')"
    } >"$PICKER_LOG"
    return 1
    ;;
  esac
}

run_install() {
  FAKE_AVAILABLE_GB=$1
  rm -f "$PICKER_LOG"
  (install_windows) >"$OUT" 2>&1
}

run_install 60
[[ -f $PICKER_LOG ]] || fail "60GB free reaches the disk picker" "$(cat "$OUT")"
grep -q '^selected=32G$' "$PICKER_LOG" || fail "60GB free defaults to 32G" "$(cat "$PICKER_LOG")"
grep -q '^options=32G $' "$PICKER_LOG" || fail "60GB free offers only 32G" "$(cat "$PICKER_LOG")"
pass "60GB free reaches the picker with 32G offered and selected"

run_install 80
[[ -f $PICKER_LOG ]] || fail "80GB free reaches the disk picker" "$(cat "$OUT")"
grep -q '^selected=64G$' "$PICKER_LOG" || fail "80GB free defaults to 64G" "$(cat "$PICKER_LOG")"
grep -q '^options=32G 64G $' "$PICKER_LOG" || fail "80GB free offers 32G and 64G" "$(cat "$PICKER_LOG")"
pass "80GB free defaults the picker to 64G"

run_install 30
[[ ! -f $PICKER_LOG ]] || fail "30GB free is rejected before the disk picker"
grep -q 'Required: 42GB' "$OUT" || fail "30GB free reports the 42GB minimum" "$(cat "$OUT")"
pass "30GB free is rejected before the picker with the 42GB minimum"
