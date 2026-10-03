#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
lock_pid=""
cleanup() {
  [[ -z $lock_pid ]] || kill "$lock_pid" 2>/dev/null || true
  rm -rf "$test_tmp"
}
trap cleanup EXIT

test_root="$test_tmp/omarchy"
test_home="$test_tmp/home"
runtime_dir="$test_tmp/runtime"
stub_bin="$test_tmp/bin"
mkdir -p "$test_root/migrations" "$test_home" "$runtime_dir" "$stub_bin"
lock_path="$runtime_dir/omarchy-update.lock"

cat >"$stub_bin/omarchy-notification-dismiss" <<'SH'
#!/bin/bash
SH
chmod +x "$stub_bin/omarchy-notification-dismiss"

cat >"$test_root/migrations/100-migration.sh" <<'SH'
echo migration >>"$TEST_CALLS"
SH

reset_state() {
  rm -rf "$test_tmp/state"
  : >"$test_tmp/calls"
}

run_migrate() {
  HOME="$test_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  OMARCHY_MIGRATION_STATE="$test_tmp/state" \
  OMARCHY_PATH="$test_root" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  TEST_CALLS="$test_tmp/calls" \
    "$ROOT/bin/omarchy-migrate" "$@"
}

# No lock file: migrations run as before.
reset_state
run_migrate >"$test_tmp/no-lock.out"
[[ $(cat "$test_tmp/calls") == "migration" ]] || fail "omarchy-migrate runs migrations without an update lock file"
pass "omarchy-migrate runs migrations without an update lock file"

# Lock file present but free: migrations run.
reset_state
: >"$lock_path"
run_migrate >"$test_tmp/free-lock.out"
[[ $(cat "$test_tmp/calls") == "migration" ]] || fail "omarchy-migrate runs migrations when the update lock is free"
pass "omarchy-migrate runs migrations when the update lock is free"

# Another process holds the update lock: skip and leave migrations pending.
reset_state
# exec so killing lock_pid releases the lock rather than orphaning its holder.
( exec 9>"$lock_path"; flock 9; exec sleep 30 ) &
lock_pid=$!
for _ in {1..50}; do
  flock -n "$lock_path" true 2>/dev/null || break
  sleep 0.1
done
if flock -n "$lock_path" true 2>/dev/null; then
  fail "test setup holds the update lock"
fi

status=0
run_migrate >"$test_tmp/held.out" 2>&1 || status=$?
(( status == 0 )) || fail "omarchy-migrate exits 0 while an update holds the lock (got $status)"
[[ ! -s $test_tmp/calls ]] || fail "omarchy-migrate does not run migrations while an update holds the lock"
grep -q 'An Omarchy update is running and will apply pending migrations' "$test_tmp/held.out" ||
  fail "omarchy-migrate explains why it skipped migrations"
run_migrate --pending >"$test_tmp/pending.out" || fail "skipped migrations stay pending"
grep -qx '100-migration.sh' "$test_tmp/pending.out" || fail "skipped migrations stay pending"
pass "omarchy-migrate defers to an update holding the lock"

# The update itself holds the lock: its own omarchy-migrate still runs them.
kill "$lock_pid" 2>/dev/null || true
wait "$lock_pid" 2>/dev/null || true
lock_pid=""
reset_state
XDG_RUNTIME_DIR="$runtime_dir" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-update-lock" run bash -c '
    HOME="$1" OMARCHY_MIGRATION_STATE="$2" OMARCHY_PATH="$3" TEST_CALLS="$4" omarchy-migrate
  ' _ "$test_home" "$test_tmp/state" "$test_root" "$test_tmp/calls" >"$test_tmp/update.out"
[[ $(cat "$test_tmp/calls") == "migration" ]] || fail "omarchy-migrate runs migrations inside the update that holds the lock"
pass "omarchy-migrate runs migrations inside the update that holds the lock"
