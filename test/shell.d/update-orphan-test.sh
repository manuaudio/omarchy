#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$stub_bin" "$test_home"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

run_orphan_checker() {
  HOME="$test_home" PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-update-orphan-pkgs"
}

write_stub pacman 'if [[ $1 == "-Qtdq" ]]; then printf "old-lib\nunused-tool\n"; exit 0; fi; exit 1'
write_stub sudo 'echo "sudo should not be called" >&2; exit 99'
write_stub gum 'echo "gum should not be called" >&2; exit 99'

run_orphan_checker >"$test_tmp/noninteractive.out" 2>"$test_tmp/noninteractive.err"
grep -q '^  old-lib$' "$test_tmp/noninteractive.out" || fail "orphan checker lists orphan packages"
grep -q 'Re-run omarchy-update-orphan-pkgs in a terminal' "$test_tmp/noninteractive.out" || fail "orphan checker does not remove packages non-interactively"
pass "orphan checker only reports orphans non-interactively"

write_stub pacman 'if [[ $1 == "-Qtdq" ]]; then exit 0; fi; exit 1'
run_orphan_checker >"$test_tmp/none.out" 2>"$test_tmp/none.err"
[[ ! -s $test_tmp/none.out ]] || fail "orphan checker stays quiet when no orphans exist"
pass "orphan checker stays quiet without orphans"

# The removal prompt needs a TTY on stdin and stdout, so the interactive cases
# run on a pty via util-linux `script -qec`; pacman, sudo and gum stay stubbed.
run_orphan_checker_tty() {
  HOME="$test_home" PATH="$stub_bin:$PATH" script -qec "$ROOT/bin/omarchy-update-orphan-pkgs" /dev/null
}

if script -qec true /dev/null >/dev/null 2>&1; then
  write_stub pacman 'if [[ $1 == "-Qtdq" ]]; then printf "old-lib\nunused-tool\n"; exit 0; fi; exit 1'
  write_stub sudo '"$@"'
  write_stub gum 'exit 0'

  status=0
  output=$(run_orphan_checker_tty | tr -d '\r') || status=$?
  (( status == 0 )) || fail "orphan checker exits 0 when pacman -Rns fails or is declined" "$output"
  grep -qF "were not removed" <<<"$output" || fail "orphan checker reports orphans left in place" "$output"
  grep -qF "omarchy update orphan-pkgs" <<<"$output" || fail "orphan checker names the route to review orphans later" "$output"
  pass "orphan checker treats a failed or declined pacman removal as non-fatal"

  write_stub pacman 'if [[ $1 == "-Qtdq" ]]; then printf "old-lib\nunused-tool\n"; exit 0; fi; [[ $1 == "-Rns" ]] && exit 0; exit 1'

  status=0
  output=$(run_orphan_checker_tty | tr -d '\r') || status=$?
  (( status == 0 )) || fail "orphan checker exits 0 after removing orphans" "$output"
  ! grep -qF "were not removed" <<<"$output" || fail "orphan checker stays quiet about leftovers after a successful removal" "$output"
  pass "orphan checker removes confirmed orphans"

  write_stub sudo 'echo "sudo should not be called" >&2; exit 99'
  write_stub gum 'exit 1'

  status=0
  output=$(run_orphan_checker_tty | tr -d '\r') || status=$?
  (( status == 0 )) || fail "orphan checker exits 0 when removal is declined" "$output"
  grep -qF "Keeping orphaned packages." <<<"$output" || fail "orphan checker keeps orphans when declined" "$output"
  ! grep -qF "sudo should not be called" <<<"$output" || fail "orphan checker does not call pacman when declined" "$output"
  pass "orphan checker keeps orphans when the prompt is declined"
else
  skip "script -qec unavailable; skipping the interactive orphan removal cases"
fi
